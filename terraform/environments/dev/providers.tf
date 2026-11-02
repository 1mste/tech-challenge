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

# O token vem da variavel de ambiente GITHUB_TOKEN — nunca de arquivo, nunca
# do state. Só é exigido quando manage_github_variable = true.
provider "github" {
  owner = length(var.github_repositories) > 0 ? split("/", var.github_repositories[0])[0] : null
}
