# ---------------------------------------------------------------------------
# CLUSTER EKS
#
# IAM Role do cluster .... EKS assume para gerenciar o control plane.
# IAM Role dos nós ....... EC2 assume para executar os workloads.
# OIDC Provider .......... habilita IRSA: dá permissão AWS aos PODS, sem
#                          precisar de access key e sem dar permissão total
#                          ao nó inteiro.
# Managed Node Group ..... as EC2 que rodam os pods.
# Addons ................. vpc-cni, coredns, kube-proxy declarados no IaC.
# ---------------------------------------------------------------------------

locals {
  cluster_name = "${var.project_name}-${var.environment}-eks"
}

# --------------------------------------------------
# IAM ROLE DO CLUSTER
# --------------------------------------------------

resource "aws_iam_role" "cluster" {
  name = "${var.project_name}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# --------------------------------------------------
# IAM ROLE DOS WORKER NODES
# --------------------------------------------------

resource "aws_iam_role" "nodes" {
  name = "${var.project_name}-${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "nodes_worker_policy" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "nodes_cni_policy" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "nodes_ecr_policy" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# --------------------------------------------------
# LOGS DO CONTROL PLANE
#
# Criado explicitamente (em vez de deixar o EKS criar) por dois motivos:
# definir retenção de 7 dias (limita custo) e garantir que o
# `terraform destroy` leve o log group embora, sem deixar resíduo na conta.
# --------------------------------------------------

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
}

# --------------------------------------------------
# CLUSTER
# --------------------------------------------------

resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  # API_AND_CONFIG_MAP mantém compatibilidade com o aws-auth legado e já
  # habilita as Access Entries modernas. bootstrap_...=true dá admin do
  # cluster a quem rodou o apply (senão você fica sem acesso ao kubectl).
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.cluster,
  ]

  tags = {
    Name = local.cluster_name
  }
}

# --------------------------------------------------
# OIDC PROVIDER — base do IRSA
# --------------------------------------------------

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = {
    Name = "${local.cluster_name}-oidc"
  }
}

# --------------------------------------------------
# MANAGED NODE GROUP
# --------------------------------------------------

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-nodes"
  node_role_arn   = aws_iam_role.nodes.arn
  version         = var.cluster_version

  subnet_ids = var.private_subnet_ids

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  # O HPA mexe no número de PODS; quem mexe no número de NÓS é o scaling
  # acima. Ignorar desired_size evita que o Terraform desfaça um scale-out
  # que tenha acontecido durante a demonstração.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    aws_iam_role_policy_attachment.nodes_worker_policy,
    aws_iam_role_policy_attachment.nodes_cni_policy,
    aws_iam_role_policy_attachment.nodes_ecr_policy,
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-nodes"
  }
}

# --------------------------------------------------
# ADDONS GERENCIADOS
#
# O EKS instalaria vpc-cni/coredns/kube-proxy sozinho, mas aí eles ficariam
# fora do código. Declarados aqui, a versão é visível e atualizável via IaC.
# coredns só agenda com nó disponível -> depends_on no node group.
# --------------------------------------------------

resource "aws_eks_addon" "this" {
  for_each = toset(var.cluster_addons)

  cluster_name = aws_eks_cluster.main.name
  addon_name   = each.value

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.main]

  tags = {
    Name = "${local.cluster_name}-${each.value}"
  }
}

# --------------------------------------------------
# ACCESS ENTRIES — quem pode usar o kubectl neste cluster
#
# bootstrap_cluster_creator_admin_permissions dá acesso SÓ a quem rodou o
# apply. Sem as entradas abaixo, o restante do time recebe
# "error: You must be logged in to the server (Unauthorized)" mesmo com
# credenciais AWS válidas — o erro mais confuso do EKS, porque parece
# problema de credencial quando na verdade é de autorização do cluster.
#
# Cada entrada liga um principal do IAM (usuário ou role) a uma política de
# acesso do Kubernetes. É o substituto moderno do ConfigMap aws-auth.
# --------------------------------------------------

resource "aws_eks_access_entry" "this" {
  for_each = var.cluster_access_entries

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"

  tags = {
    Name = "${local.cluster_name}-access-${each.key}"
  }
}

resource "aws_eks_access_policy_association" "this" {
  for_each = var.cluster_access_entries

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/${each.value.policy}"

  access_scope {
    # Sem namespaces = acesso ao cluster inteiro. Com namespaces = restrito
    # àquela lista, útil para dar acesso só ao time de uma aplicação.
    type       = each.value.namespaces == null ? "cluster" : "namespace"
    namespaces = each.value.namespaces
  }

  depends_on = [aws_eks_access_entry.this]
}
