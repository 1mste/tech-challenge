output "bucket_name" {
  description = "Nome do bucket — copie para o backend.tf da stack dev"
  value       = aws_s3_bucket.tfstate.id
}

output "backend_config" {
  description = "Bloco pronto para colar em environments/dev/backend.tf"
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.tfstate.id}"
        key          = "togglemaster/dev/terraform.tfstate"
        region       = "${var.aws_region}"
        encrypt      = true
        use_lockfile = true
      }
    }
  EOT
}
