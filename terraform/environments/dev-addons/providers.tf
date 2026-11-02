# ---------------------------------------------------------------------------
# Esta stack conversa com um cluster que JÁ existe. Ela o descobre por data
# source (pelo nome), não por output de recurso — é isso que mantém plan e
# destroy estáveis.
# ---------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Phase       = "tech-challenge-fase-3"
    }
  }
}

data "aws_eks_cluster" "main" {
  name = "${var.project_name}-${var.environment}-eks"
}

data "aws_eks_cluster_auth" "main" {
  name = data.aws_eks_cluster.main.name
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

# A role IRSA do KEDA e criada pela stack de infraestrutura (modules/irsa).
# Aqui ela e descoberta pelo NOME, no mesmo espirito do cluster acima: data
# source em vez de output entre stacks, para nao acoplar os states.
data "aws_iam_role" "keda" {
  name = "${var.project_name}-${var.environment}-keda-irsa"
}
