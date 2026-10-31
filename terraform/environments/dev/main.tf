# ---------------------------------------------------------------------------
# TOGGLEMASTER — ambiente dev
#
# Ordem de dependência real (o Terraform resolve sozinho pelos outputs):
#
#   network  ->  eks  ->  irsa
#                  |
#                  +-->  rds / redis   (precisam do SG do cluster)
#
#   dynamodb, sqs, ecr  ->  independentes
#   github-oidc         ->  precisa dos ARNs do ECR
# ---------------------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  # Sem NAT os nós em subnet privada nunca ficam Ready.
  enable_nat_gateway       = true
  single_nat_gateway       = var.single_nat_gateway
  enable_gateway_endpoints = true
}

module "eks" {
  source = "../../modules/eks"

  project_name    = var.project_name
  environment     = var.environment
  cluster_version = var.cluster_version

  private_subnet_ids = module.network.private_subnet_ids
  public_subnet_ids  = module.network.public_subnet_ids

  endpoint_public_access  = true
  endpoint_private_access = true
  public_access_cidrs     = var.public_access_cidrs

  # Sem isto, só quem roda o apply consegue usar o kubectl.
  cluster_access_entries = var.team_access_entries

  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size      = 20
}

# --------------------------------------------------
# DADOS
# --------------------------------------------------

module "rds" {
  source = "../../modules/rds"

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  cluster_security_group_id = module.eks.cluster_security_group_id

  db_master_username = var.db_master_username
  instance_class     = var.db_instance_class
}

module "redis" {
  source = "../../modules/redis"

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  cluster_security_group_id = module.eks.cluster_security_group_id

  node_type = var.redis_node_type
}

module "dynamodb" {
  source = "../../modules/dynamodb"

  project_name = var.project_name
  environment  = var.environment
  table_name   = var.dynamodb_table_name
}

module "sqs" {
  source = "../../modules/sqs"

  project_name = var.project_name
  environment  = var.environment

  queue_name                 = var.sqs_queue_name
  visibility_timeout_seconds = 60
}

# --------------------------------------------------
# PERMISSÕES DOS PODS (IRSA)
# --------------------------------------------------

module "irsa" {
  source = "../../modules/irsa"

  project_name = var.project_name
  environment  = var.environment

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  sqs_queue_arn      = module.sqs.queue_arn
  sqs_dlq_arn        = module.sqs.dlq_arn
  dynamodb_table_arn = module.dynamodb.table_arn
}

# --------------------------------------------------
# IMAGENS
# --------------------------------------------------

module "ecr" {
  source = "../../modules/ecr"

  project_name     = var.project_name
  environment      = var.environment
  repository_names = var.ecr_repository_names

  scan_on_push = true
  force_delete = true
}

# --------------------------------------------------
# ITEM 2 — acesso do GitHub Actions ao ECR, sem access key.
# Só é criado quando você informar github_repositories.
# --------------------------------------------------

module "github_oidc" {
  source = "../../modules/github-oidc"

  count = length(var.github_repositories) > 0 ? 1 : 0

  project_name = var.project_name
  environment  = var.environment

  github_repositories  = var.github_repositories
  ecr_repository_arns  = values(module.ecr.repository_arns)
  create_oidc_provider = var.create_github_oidc_provider
}
