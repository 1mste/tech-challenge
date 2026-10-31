provider "aws" {
  region = var.aws_region

  # Aplicadas a todo recurso que suporta tags. Evita repetir o bloco em
  # cada módulo e deixa claro no console que nada ali foi feito na mão.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Phase       = "tech-challenge-fase-3"
    }
  }
}
