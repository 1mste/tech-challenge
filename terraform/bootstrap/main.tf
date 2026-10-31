# ---------------------------------------------------------------------------
# BOOTSTRAP DO BACKEND REMOTO
#
# Problema do ovo e da galinha: a stack dev guarda o state num bucket S3,
# mas alguém precisa criar esse bucket antes. Esta stack faz isso, e só
# isso, rodando com state LOCAL (é a única exceção permitida).
#
#   cd terraform/bootstrap
#   terraform init && terraform apply
#   # copie o output bucket_name para terraform/environments/dev/backend.tf
#   cd ../environments/dev && terraform init
#
# Rode uma vez por conta. NÃO destrua enquanto houver ambiente de pé: o
# state de todos eles mora aqui dentro.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  # O nome do bucket S3 é global; o ID da conta garante unicidade.
  bucket_name = coalesce(var.bucket_name, "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}")
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  tags = {
    Name      = local.bucket_name
    Purpose   = "terraform-remote-state"
    ManagedBy = "Terraform"
  }
}

# Versionamento é o que permite recuperar um state corrompido ou sobrescrito.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# O state contém endpoints, ARNs e eventualmente segredos: nunca público.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Limita o custo de guardar versões antigas do state indefinidamente.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
