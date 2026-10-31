output "cluster_name" {
  description = "Nome do cluster EKS"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint da API do Kubernetes"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_arn" {
  description = "ARN do cluster EKS"
  value       = aws_eks_cluster.main.arn
}

output "cluster_version" {
  description = "Versão do Kubernetes em execução"
  value       = aws_eks_cluster.main.version
}

output "cluster_security_group_id" {
  description = "Security Group gerenciado pelo EKS (associado aos nós e ao control plane)"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "CA do cluster, em base64 (usada pelo kubeconfig)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "node_group_name" {
  description = "Nome do Managed Node Group"
  value       = aws_eks_node_group.main.node_group_name
}

output "cluster_iam_role_arn" {
  description = "ARN da IAM Role do cluster"
  value       = aws_iam_role.cluster.arn
}

output "node_iam_role_arn" {
  description = "ARN da IAM Role dos nós"
  value       = aws_iam_role.nodes.arn
}

output "oidc_provider_arn" {
  description = "ARN do OIDC Provider — base do IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "URL do emissor OIDC, sem o prefixo https://"
  value       = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}

output "cluster_access_entries" {
  description = "Quem tem acesso ao kubectl, além de quem rodou o apply"
  value = {
    for k, v in var.cluster_access_entries :
    k => { principal = v.principal_arn, policy = v.policy, namespaces = v.namespaces }
  }
}
