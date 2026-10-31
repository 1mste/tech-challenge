# ---------------------------------------------------------------------------
# GITHUB ACTIONS OIDC  —  pré-requisito do ITEM 2 (CI/CD & DevSecOps)
#
# Dá ao workflow do GitHub permissão de push no ECR SEM access key de longa
# duração guardada em secret do repositório. O Actions troca o token OIDC
# dele por credenciais temporárias da AWS.
#
# Atenção: este OIDC provider é DIFERENTE do OIDC do EKS (módulo eks). Um
# autentica o GitHub perante a AWS; o outro autentica os pods.
#
# No workflow:
#   permissions:
#     id-token: write
#     contents: read
#   steps:
#     - uses: aws-actions/configure-aws-credentials@v4
#       with:
#         role-to-assume: <output ci_role_arn>
#         aws-region: us-east-1
# ---------------------------------------------------------------------------

locals {
  name       = "${var.project_name}-${var.environment}"
  oidc_host  = "token.actions.githubusercontent.com"
  issuer_url = "https://token.actions.githubusercontent.com"

  # Uma condição por repositório autorizado. O sufixo define QUEM pode
  # assumir: ":*" = qualquer branch/PR; "ref:refs/heads/main" = só a main.
  allowed_subjects = [
    for repo in var.github_repositories : "repo:${repo}:*"
  ]

  oidc_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn
}

data "tls_certificate" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url = local.issuer_url
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = local.issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]

  tags = {
    Name = "${local.name}-github-oidc"
  }
}

# --------------------------------------------------
# ROLE ASSUMIDA PELO PIPELINE
# --------------------------------------------------

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Sem esta condição, QUALQUER repositório do GitHub poderia assumir a
    # role. É a linha mais importante do módulo.
    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = local.allowed_subjects
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = "${local.name}-github-actions-ci"
  description        = "Assumida pelos workflows do GitHub Actions para publicar imagens no ECR"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Name = "${local.name}-github-actions-ci"
  }
}

data "aws_iam_policy_document" "ecr_push" {
  # GetAuthorizationToken não aceita recurso específico — é sempre "*".
  statement {
    sid       = "EcrLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushPull"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]

    # Restrito aos 5 repositórios do projeto.
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "${local.name}-ecr-push"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
