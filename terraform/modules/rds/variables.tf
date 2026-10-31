variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Ambiente da infraestrutura"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC onde os bancos serão criados"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs das subnets privadas"
  type        = list(string)
}

variable "cluster_security_group_id" {
  description = "Security Group do cluster EKS — única origem liberada na porta 5432"
  type        = string
}

variable "extra_allowed_cidrs" {
  description = "CIDRs adicionais com acesso ao PostgreSQL (bastion/VPN). Vazio mantém o banco fechado."
  type        = list(string)
  default     = []
}

variable "db_master_username" {
  description = "Usuário administrador dos bancos"
  type        = string
  default     = "tmadmin"
}

variable "engine_version" {
  description = "Versão do PostgreSQL. Apenas a major mantém a minor sempre atual."
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "Classe das instâncias RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Armazenamento por instância, em GiB"
  type        = number
  default     = 20
}

variable "backup_retention_period" {
  description = "Dias de retenção de backup. 0 desliga (ambiente de estudo)."
  type        = number
  default     = 0
}
