#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Imprime a tabela de conexões a partir do Terraform.
#
# Substitui o antigo 04-outputs.sh: em vez de consultar a AWS recurso a
# recurso, lê o state. Se algo não aparecer, a infra ainda não foi aplicada.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

if ! terraform -chdir="$TF_DIR" show >/dev/null 2>&1; then
  echo "ERRO: Terraform não inicializado em $TF_DIR. Rode 'terraform init' lá." >&2
  exit 1
fi

echo "==================== TOGGLEMASTER — HANDOFF ===================="
echo
echo "Cluster ........ $(tf_out cluster_name)"
echo "Kubeconfig ..... $(tf_out kubeconfig_command)"
echo
echo "--- Dados ---"
terraform -chdir="$TF_DIR" output rds_addresses 2>/dev/null || true
echo "Redis .......... $(tf_out redis_url)"
echo "SQS ............ $(tf_out sqs_queue_url)"
echo "DynamoDB ....... $(tf_out dynamodb_table_name)"
echo
echo "--- Imagens ---"
echo "Registry ....... $(tf_out ecr_registry)"
echo "Login .......... $(tf_out ecr_login_command)"
echo
echo "--- Secrets (credenciais dos bancos) ---"
terraform -chdir="$TF_DIR" output rds_secret_names 2>/dev/null || true
echo
echo "--- IRSA (annotations das ServiceAccounts) ---"
terraform -chdir="$TF_DIR" output service_account_annotations 2>/dev/null || true
echo
echo "--- Item 2: role do GitHub Actions ---"
echo "$(tf_out github_actions_role_arn || echo '(github_repositories não definido)')"
echo
echo "Variáveis completas por serviço:"
echo "  terraform -chdir=$TF_DIR output -json service_env | jq"
echo "================================================================"
