variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Ambiente da infraestrutura"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN do OIDC Provider do cluster EKS"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL do emissor OIDC, sem o prefixo https://"
  type        = string
}

variable "sqs_queue_arn" {
  description = "ARN da fila SQS principal"
  type        = string
}

variable "sqs_dlq_arn" {
  description = "ARN da dead-letter queue"
  type        = string
  default     = ""
}

variable "dynamodb_table_arn" {
  description = "ARN da tabela DynamoDB de analytics"
  type        = string
}

variable "service_accounts" {
  description = "Mapa de identificador => namespace/service account do Kubernetes"
  type = map(object({
    namespace       = string
    service_account = string
  }))

  default = {
    analytics = {
      namespace       = "analytics-service"
      service_account = "analytics-sa"
    }
    evaluation = {
      namespace       = "evaluation-service"
      service_account = "evaluation-sa"
    }
  }

  validation {
    condition     = alltrue([for k in ["analytics", "evaluation"] : contains(keys(var.service_accounts), k)])
    error_message = "service_accounts precisa conter as chaves 'analytics' e 'evaluation'."
  }
}
