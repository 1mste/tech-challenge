output "role_arns" {
  description = "ARNs das roles IRSA, por serviço. Vão na annotation eks.amazonaws.com/role-arn das ServiceAccounts."
  value = {
    for key, role in aws_iam_role.this : key => role.arn
  }
}

output "service_account_annotations" {
  description = "Annotation pronta para colar em cada ServiceAccount do repositório GitOps"
  value = {
    for key, sa in var.service_accounts :
    "${sa.namespace}/${sa.service_account}" => {
      "eks.amazonaws.com/role-arn" = aws_iam_role.this[key].arn
    }
  }
}
