variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Ambiente da infraestrutura"
  type        = string
}

variable "aws_region" {
  description = "Região AWS (usada nos VPC Endpoints)"
  type        = string
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Zonas de disponibilidade utilizadas"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "EKS, RDS e ElastiCache exigem no mínimo 2 zonas de disponibilidade."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Cria NAT Gateway para dar saída de internet às subnets privadas. OBRIGATÓRIO para os nós do EKS ficarem Ready."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Usa um único NAT para todas as AZs (mais barato) em vez de um por AZ (mais resiliente)"
  type        = bool
  default     = true
}

variable "enable_gateway_endpoints" {
  description = "Cria VPC Endpoints Gateway para S3 e DynamoDB (gratuitos, reduzem o tráfego pago pelo NAT)"
  type        = bool
  default     = true
}
