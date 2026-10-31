# ---------------------------------------------------------------------------
# Nenhuma variável aqui é obrigatória: `terraform plan` roda sem tfvars.
# Senhas não aparecem nesta lista de propósito — são geradas pelo módulo rds
# e guardadas no Secrets Manager.
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "Região AWS do projeto"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto, usado como prefixo dos recursos"
  type        = string
  default     = "togglemaster"
}

variable "environment" {
  description = "Ambiente da infraestrutura"
  type        = string
  default     = "dev"
}

# --- Rede ---

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Zonas de disponibilidade"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "single_nat_gateway" {
  description = "Um NAT para todas as AZs (~US$ 32/mês) em vez de um por AZ"
  type        = bool
  default     = true
}

# --- Cluster ---

variable "cluster_version" {
  description = "Versão do Kubernetes"
  type        = string
  default     = "1.36"
}

variable "node_instance_types" {
  description = "Tipos de instância dos nós. t3.medium comporta os 5 serviços + ingress + metrics-server."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Nós desejados"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Nós mínimos"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Nós máximos — espaço para o HPA escalar"
  type        = number
  default     = 4
}

variable "public_access_cidrs" {
  description = "CIDRs com acesso ao endpoint público da API do cluster"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- Dados ---

variable "db_master_username" {
  description = "Usuário administrador das instâncias RDS"
  type        = string
  default     = "tmadmin"
}

variable "db_instance_class" {
  description = "Classe das instâncias RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "redis_node_type" {
  description = "Classe do nó Redis"
  type        = string
  default     = "cache.t3.micro"
}

variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB. Precisa bater com AWS_DYNAMODB_TABLE no analytics-service."
  type        = string
  default     = "ToggleMasterAnalytics"
}

variable "sqs_queue_name" {
  description = "Nome da fila SQS"
  type        = string
  default     = "togglemaster-analytics-events"
}

# --- Imagens ---

variable "ecr_repository_names" {
  description = "Repositórios ECR, um por microsserviço"
  type        = list(string)
  default = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service",
  ]
}

# --- Item 2: CI/CD ---

variable "github_repositories" {
  description = "Repositórios 'org/repo' autorizados a publicar no ECR via OIDC. Vazio desliga o módulo."
  type        = list(string)
  default     = []
}

variable "create_github_oidc_provider" {
  description = "Crie false se a conta já tiver o OIDC provider do GitHub (é único por conta)"
  type        = bool
  default     = true
}

# --- Acesso do time ao cluster ---

variable "team_access_entries" {
  description = <<-EOT
    Quem, além de quem roda o apply, pode usar o kubectl. Sem isto o time
    recebe "Unauthorized" mesmo com credenciais AWS válidas.
    Exemplo:
      team_access_entries = {
        joao  = { principal_arn = "arn:aws:iam::698172256617:user/joao" }
        maria = { principal_arn = "arn:aws:iam::698172256617:user/maria" }
      }
  EOT

  type = map(object({
    principal_arn = string
    policy        = optional(string, "AmazonEKSClusterAdminPolicy")
    namespaces    = optional(list(string), null)
  }))

  default = {}
}
