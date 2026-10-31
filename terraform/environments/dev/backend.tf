# ---------------------------------------------------------------------------
# BACKEND REMOTO (exigência da Fase 3: o tfstate não pode ficar local).
#
# O bucket é criado pela stack terraform/bootstrap, que roda uma única vez
# com state local. Depois de criá-lo:
#
#   terraform init -migrate-state
#
# use_lockfile = true usa o lock nativo do S3 (Terraform >= 1.10), sem
# precisar de tabela DynamoDB para lock.
#
# Se o nome do bucket for diferente, ajuste aqui E em bootstrap.
# ---------------------------------------------------------------------------

terraform {
  backend "s3" {
    bucket       = "togglemaster-tfstate-698172256617"
    key          = "togglemaster/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
