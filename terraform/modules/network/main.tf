# ---------------------------------------------------------------------------
# NETWORKING — VPC, subnets públicas/privadas, IGW, NAT e route tables.
#
# Decisão importante: os nós do EKS ficam em subnets PRIVADAS. Para que eles
# consigam baixar imagens do ECR, registrar-se na API do EKS e enviar logs,
# a route table privada PRECISA de uma rota default. Sem NAT (ou VPC
# Endpoints), os nós sobem mas nunca ficam Ready — é a falha mais comum de
# EKS provisionado via Terraform.
# ---------------------------------------------------------------------------

locals {
  name = "${var.project_name}-${var.environment}"

  # Nome do cluster EKS, replicado aqui porque as subnets precisam da tag
  # kubernetes.io/cluster/<nome> para que o Load Balancer Controller e o
  # Nginx Ingress descubram onde criar o NLB.
  cluster_name = "${var.project_name}-${var.environment}-eks"

  # 1 NAT compartilhado (barato, ~US$ 32/mês) ou 1 por AZ (resiliente, caro).
  nat_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.public_subnet_cidrs)) : 0
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name}-igw"
  }
}

# --------------------------------------------------
# SUBNETS
# --------------------------------------------------

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${count.index + 1}"
    # "elb" = aqui o Nginx Ingress cria o Load Balancer público.
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                          = "${local.name}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

# --------------------------------------------------
# NAT GATEWAY — saída de internet para as subnets privadas
# --------------------------------------------------

resource "aws_eip" "nat" {
  count = local.nat_count

  domain = "vpc"

  tags = {
    Name = "${local.name}-nat-eip-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${local.name}-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}

# --------------------------------------------------
# ROUTE TABLES
# --------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Uma route table privada por subnet: com NAT por AZ, cada uma aponta para o
# seu próprio NAT. Com NAT único, todas apontam para o mesmo.
resource "aws_route_table" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name}-private-rt-${count.index + 1}"
  }
}

resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? length(aws_route_table.private) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# --------------------------------------------------
# GATEWAY VPC ENDPOINTS (S3 e DynamoDB)
#
# São GRATUITOS e tiram do NAT todo o tráfego de pull de imagem (as camadas
# do ECR vivem no S3) e de escrita do analytics-service no DynamoDB.
# Reduz a conta de transferência do NAT de forma relevante.
# --------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_gateway_endpoints ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = {
    Name = "${local.name}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  count = var.enable_gateway_endpoints ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = {
    Name = "${local.name}-dynamodb-endpoint"
  }
}
