variable "enable_metrics_server" {
  description = "Instala o Metrics Server (necessário para o HPA)"
  type        = bool
  default     = true
}

variable "metrics_server_version" {
  description = "Versão do chart do Metrics Server"
  type        = string
  default     = "3.12.2"
}

variable "enable_ingress_nginx" {
  description = "Instala o Nginx Ingress Controller (cria um NLB na AWS)"
  type        = bool
  default     = true
}

variable "ingress_nginx_version" {
  description = "Versão do chart do ingress-nginx"
  type        = string
  default     = "4.14.5"
}

variable "ingress_replica_count" {
  description = "Réplicas do controller do Ingress"
  type        = number
  default     = 2
}

variable "enable_argocd" {
  description = "Instala o ArgoCD (item 3 — GitOps)"
  type        = bool
  default     = true
}

variable "argocd_version" {
  description = "Versão do chart do ArgoCD"
  type        = string
  default     = "10.11.3"
}

variable "argocd_namespace" {
  description = "Namespace do ArgoCD"
  type        = string
  default     = "argocd"
}

variable "argocd_service_type" {
  description = "ClusterIP (acesso via port-forward, sem custo extra) ou LoadBalancer (cria outro NLB)"
  type        = string
  default     = "ClusterIP"
}

variable "enable_keda" {
  description = "Instala o KEDA — necessário para o ScaledObject do analytics-service"
  type        = bool
  default     = true
}

variable "keda_version" {
  description = "Versão do chart do KEDA"
  type        = string
  default     = "2.20.2"
}

variable "keda_namespace" {
  description = "Namespace do KEDA"
  type        = string
  default     = "keda"
}
