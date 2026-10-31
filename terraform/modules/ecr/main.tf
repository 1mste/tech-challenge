# ---------------------------------------------------------------------------
# ECR — um repositório por microsserviço.
#
# Os nomes ficam SEM prefixo de projeto de propósito: é o que o
# 05-build-push-ecr.sh e os manifestos já esperam. Trocar para
# "togglemaster/auth-service" quebraria o push e os Deployments.
#
# scan_on_push ligado: é a primeira barreira de DevSecOps do item 2, e roda
# mesmo em imagem enviada fora do pipeline.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "services" {
  for_each = toset(var.repository_names)

  name                 = "${var.repository_prefix}${each.value}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name    = each.value
    Service = each.value
  }
}

# Evita o acúmulo de imagens antigas (e o custo de armazenamento junto).
resource "aws_ecr_lifecycle_policy" "services" {
  for_each = aws_ecr_repository.services

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter apenas as ${var.keep_last_images} imagens mais recentes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_last_images
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
