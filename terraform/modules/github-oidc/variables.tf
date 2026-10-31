variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Ambiente da infraestrutura"
  type        = string
}

variable "github_repositories" {
  description = "Repositórios autorizados a assumir a role, no formato 'org/repo'"
  type        = list(string)

  validation {
    condition     = alltrue([for r in var.github_repositories : can(regex("^[^/]+/[^/]+$", r))])
    error_message = "Cada entrada deve estar no formato 'org/repo'."
  }
}

variable "ecr_repository_arns" {
  description = "ARNs dos repositórios ECR em que o pipeline pode publicar"
  type        = list(string)
}

variable "create_oidc_provider" {
  description = "Cria o OIDC provider do GitHub. Use false se a conta já tiver um (ele é único por conta)."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN do OIDC provider já existente, quando create_oidc_provider = false"
  type        = string
  default     = ""
}
