variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "togglemaster"
}

variable "environment" {
  description = "Ambiente"
  type        = string
  default     = "dev"
}

variable "enable_argocd" {
  description = "Instala o ArgoCD (item 3)"
  type        = bool
  default     = true
}

variable "argocd_service_type" {
  description = "ClusterIP evita um segundo Load Balancer e seu custo"
  type        = string
  default     = "ClusterIP"
}

variable "enable_keda" {
  description = "Instala o KEDA (necessário para o autoescalonamento do analytics-service)"
  type        = bool
  default     = true
}
