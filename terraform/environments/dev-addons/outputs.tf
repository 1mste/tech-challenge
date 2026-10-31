output "cluster_name" {
  description = "Cluster em que os addons foram instalados"
  value       = data.aws_eks_cluster.main.name
}

output "argocd_initial_password_command" {
  description = "Senha inicial do admin do ArgoCD"
  value       = module.k8s_addons.argocd_initial_password_command
}

output "argocd_port_forward_command" {
  description = "Abre a interface do ArgoCD localmente"
  value       = module.k8s_addons.argocd_port_forward_command
}

output "ingress_hostname_command" {
  description = "Endereço público do Nginx Ingress (o NLB)"
  value       = module.k8s_addons.ingress_hostname_command
}

output "keda_namespace" {
  description = "Namespace do KEDA"
  value       = module.k8s_addons.keda_namespace
}
