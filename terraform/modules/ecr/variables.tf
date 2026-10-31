variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Ambiente da infraestrutura"
  type        = string
}

variable "repository_names" {
  description = "Nomes dos repositórios dos microsserviços"
  type        = list(string)

  validation {
    condition     = length(var.repository_names) == 5
    error_message = "Devem ser informados exatamente cinco repositórios, um por microsserviço."
  }
}

variable "repository_prefix" {
  description = "Prefixo dos repositórios. Vazio mantém compatibilidade com os scripts e manifestos existentes."
  type        = string
  default     = ""
}

variable "image_tag_mutability" {
  description = "MUTABLE permite sobrescrever tags; IMMUTABLE é mais seguro mas impede reusar 'latest'."
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Scan de vulnerabilidades automático a cada push"
  type        = bool
  default     = true
}

variable "force_delete" {
  description = "Permite destruir o repositório mesmo com imagens dentro. Essencial para um terraform destroy limpo."
  type        = bool
  default     = true
}

variable "keep_last_images" {
  description = "Quantidade de imagens mantidas pela lifecycle policy"
  type        = number
  default     = 5
}
