variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Ambiente da infraestrutura"
  type        = string
}

variable "cluster_version" {
  description = "Versão do Kubernetes no EKS"
  type        = string
  default     = "1.36"
}

variable "private_subnet_ids" {
  description = "IDs das subnets privadas onde ficam os nós"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "IDs das subnets públicas (usadas pelo Load Balancer do Ingress)"
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Permite acesso público ao endpoint da API do cluster"
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Permite acesso ao endpoint da API pela VPC"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs autorizados a acessar o endpoint público. Restrinja ao seu IP em ambiente real."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enabled_cluster_log_types" {
  description = "Tipos de log do control plane enviados ao CloudWatch"
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "log_retention_days" {
  description = "Retenção dos logs do control plane, em dias (limita o custo do CloudWatch)"
  type        = number
  default     = 7
}

variable "cluster_addons" {
  description = "Addons gerenciados do EKS"
  type        = list(string)
  default     = ["vpc-cni", "coredns", "kube-proxy"]
}

variable "node_instance_types" {
  description = "Tipos de instância EC2 dos nós"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND ou SPOT"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type deve ser ON_DEMAND ou SPOT."
  }
}

variable "node_desired_size" {
  description = "Quantidade desejada de nós"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Quantidade mínima de nós"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Quantidade máxima de nós"
  type        = number
  default     = 4
}

variable "node_disk_size" {
  description = "Tamanho do disco dos nós, em GiB"
  type        = number
  default     = 20
}

variable "cluster_access_entries" {
  description = <<-EOT
    Pessoas/roles que podem usar o kubectl no cluster, além de quem rodou o apply.
    Chave = apelido. policy: AmazonEKSClusterAdminPolicy (tudo),
    AmazonEKSAdminPolicy (admin sem gerenciar acesso), AmazonEKSEditPolicy
    (mexe em recursos), AmazonEKSViewPolicy (só leitura).
    namespaces = null concede acesso ao cluster inteiro.
  EOT

  type = map(object({
    principal_arn = string
    policy        = optional(string, "AmazonEKSClusterAdminPolicy")
    namespaces    = optional(list(string), null)
  }))

  default = {}
}
