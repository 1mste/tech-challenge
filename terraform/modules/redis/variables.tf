variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Ambiente da infraestrutura"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs das subnets privadas"
  type        = list(string)
}

variable "cluster_security_group_id" {
  description = "Security Group do cluster EKS — única origem liberada na porta 6379"
  type        = string
}

variable "node_type" {
  description = "Classe do nó Redis"
  type        = string
  default     = "cache.t3.micro"
}

variable "engine_version" {
  description = "Versão do Redis"
  type        = string
  default     = "7.1"
}

variable "parameter_group_name" {
  description = "Parameter group. Precisa bater com a família da engine_version."
  type        = string
  default     = "default.redis7"
}
