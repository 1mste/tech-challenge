output "ci_role_arn" {
  description = "ARN da role para 'role-to-assume' no aws-actions/configure-aws-credentials"
  value       = aws_iam_role.ci.arn
}

output "oidc_provider_arn" {
  description = "ARN do OIDC provider do GitHub"
  value       = local.oidc_arn
}
