output "argocd_namespace" {
  description = "Namespace onde o ArgoCD foi instalado"
  value       = var.enable_argocd ? var.argocd_namespace : ""
}

output "argocd_initial_password_command" {
  description = "Comando para obter a senha inicial do usuário admin do ArgoCD"
  value       = "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_port_forward_command" {
  description = "Comando para abrir a interface do ArgoCD em http://localhost:8080"
  value       = "kubectl -n ${var.argocd_namespace} port-forward svc/argocd-server 8080:80"
}

output "ingress_hostname_command" {
  description = "Comando para descobrir o endereço público do Nginx Ingress"
  value       = "kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "keda_namespace" {
  description = "Namespace onde o KEDA foi instalado"
  value       = var.enable_keda ? var.keda_namespace : ""
}
