#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Variáveis compartilhadas pelos scripts auxiliares.
#
# MUDOU NA FASE 3: a fonte da verdade da infraestrutura agora é o Terraform,
# não este arquivo. O que está aqui são apenas os nomes fixos (região,
# repositórios) e valores derivados do `terraform output`.
#
# Uso: os scripts fazem `source env.sh`.
# ---------------------------------------------------------------------------

export REGION="${REGION:-us-east-1}"
export PROJECT_NAME="${PROJECT_NAME:-togglemaster}"
export ENVIRONMENT="${ENVIRONMENT:-dev}"

export TF_DIR="${TF_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/terraform/environments/dev}"

# Um repositório ECR por microsserviço (sem prefixo — bate com o Terraform).
export ECR_REPOS=("auth-service" "flag-service" "targeting-service" "evaluation-service" "analytics-service")

export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
export CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eks"

# tf_out <nome-do-output> — lê um output do Terraform, vazio se não existir.
tf_out() {
  terraform -chdir="$TF_DIR" output -raw "$1" 2>/dev/null
}
export -f tf_out
