# ---------------------------------------------------------------------------
# Outputs = contrato de entrega para os itens 2 e 3.
#
# Tudo que os manifestos do GitOps e os workflows do CI precisam saber sai
# daqui. Nenhum valor é copiado à mão do console.
#
#   terraform output -json service_env  > ../../../gitops/env.json
# ---------------------------------------------------------------------------

# --- Rede ---

output "vpc_id" {
  description = "ID da VPC"
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas"
  value       = module.network.private_subnet_ids
}

output "nat_public_ips" {
  description = "IPs de saída das subnets privadas"
  value       = module.network.nat_public_ips
}

# --- Cluster ---

output "cluster_name" {
  description = "Nome do cluster EKS"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint da API do Kubernetes"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Versão do Kubernetes"
  value       = module.eks.cluster_version
}

output "cluster_security_group_id" {
  description = "Security Group do cluster"
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "OIDC provider do cluster (base do IRSA)"
  value       = module.eks.oidc_provider_arn
}

output "kubeconfig_command" {
  description = "Comando para configurar o kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# --- Dados ---

output "rds_addresses" {
  description = "Endpoints das 3 instâncias PostgreSQL"
  value       = module.rds.db_addresses
}

output "rds_secret_names" {
  description = "Secrets do Secrets Manager com as credenciais de cada banco"
  value       = module.rds.secret_names
}

output "rds_secret_arns" {
  description = "ARNs das secrets — usados pelo External Secrets Operator"
  value       = module.rds.secret_arns
}

output "redis_url" {
  description = "REDIS_URL do evaluation-service"
  value       = module.redis.redis_url
}

output "sqs_queue_url" {
  description = "AWS_SQS_URL do evaluation-service e do analytics-service"
  value       = module.sqs.queue_url
}

output "sqs_queue_arn" {
  description = "ARN da fila (usado pelo ScaledObject do KEDA, se adotado)"
  value       = module.sqs.queue_arn
}

output "dynamodb_table_name" {
  description = "AWS_DYNAMODB_TABLE do analytics-service"
  value       = module.dynamodb.table_name
}

# --- Imagens ---

output "ecr_repository_urls" {
  description = "URLs dos repositórios ECR, por serviço"
  value       = module.ecr.repository_urls
}

output "ecr_registry" {
  description = "Host do registry para o docker login"
  value       = module.ecr.registry_url
}

output "ecr_login_command" {
  description = "Comando de login no ECR"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${module.ecr.registry_url}"
}

# --- Item 2: CI/CD ---

output "github_actions_role_arn" {
  description = "Role a informar em 'role-to-assume' nos workflows. Vazia se github_repositories não foi definido."
  value       = length(module.github_oidc) > 0 ? module.github_oidc[0].ci_role_arn : ""
}

# --- Item 3: GitOps ---

output "irsa_role_arns" {
  description = "Roles IRSA por serviço — vão na annotation das ServiceAccounts"
  value       = module.irsa.role_arns
}

output "service_account_annotations" {
  description = "Annotations prontas para as ServiceAccounts do repositório GitOps"
  value       = module.irsa.service_account_annotations
}

output "service_env" {
  description = "Mapa completo de variáveis de ambiente por microsserviço, para montar ConfigMaps e Secrets do GitOps"

  value = {
    auth-service = {
      PORT         = "8001"
      DATABASE_URL = "secretsmanager:${module.rds.secret_names["auth"]}:DATABASE_URL"
    }

    flag-service = {
      PORT             = "8002"
      AUTH_SERVICE_URL = "http://auth-service.auth-service.svc.cluster.local:8001"
      DATABASE_URL     = "secretsmanager:${module.rds.secret_names["flag"]}:DATABASE_URL"
    }

    targeting-service = {
      PORT             = "8003"
      AUTH_SERVICE_URL = "http://auth-service.auth-service.svc.cluster.local:8001"
      DATABASE_URL     = "secretsmanager:${module.rds.secret_names["targeting"]}:DATABASE_URL"
    }

    evaluation-service = {
      PORT                  = "8004"
      REDIS_URL             = module.redis.redis_url
      AWS_REGION            = var.aws_region
      AWS_SQS_URL           = module.sqs.queue_url
      FLAG_SERVICE_URL      = "http://flag-service.flag-service.svc.cluster.local:8002"
      TARGETING_SERVICE_URL = "http://targeting-service.targeting-service.svc.cluster.local:8003"
      SERVICE_ACCOUNT       = "evaluation-sa"
      IRSA_ROLE_ARN         = module.irsa.role_arns["evaluation"]
    }

    analytics-service = {
      PORT               = "8005"
      AWS_REGION         = var.aws_region
      AWS_SQS_URL        = module.sqs.queue_url
      AWS_DYNAMODB_TABLE = module.dynamodb.table_name
      SERVICE_ACCOUNT    = "analytics-sa"
      IRSA_ROLE_ARN      = module.irsa.role_arns["analytics"]
    }
  }
}

output "team_cluster_access" {
  description = "Pessoas do time com acesso ao kubectl. Vazio = só quem rodou o apply."
  value       = module.eks.cluster_access_entries
}

output "aws_region" {
  description = "Região em uso — consumida pelos scripts de apoio"
  value       = var.aws_region
}
