variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Ambiente da infraestrutura"
  type        = string
}

variable "table_name" {
  description = "Nome da tabela DynamoDB"
  type        = string
  default     = "ToggleMasterAnalytics"
}

variable "hash_key" {
  description = "Partition key. Precisa bater com o código do analytics-service."
  type        = string
  default     = "event_id"
}

variable "billing_mode" {
  description = "PAY_PER_REQUEST evita custo de capacidade ociosa"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "point_in_time_recovery" {
  description = "Backup contínuo. Gera custo; desligado em ambiente de estudo."
  type        = bool
  default     = false
}
