variable "aws_region" {
  description = "Região do bucket de state"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "togglemaster"
}

variable "bucket_name" {
  description = "Nome do bucket. Vazio gera '<project>-tfstate-<account_id>'."
  type        = string
  default     = null
}
