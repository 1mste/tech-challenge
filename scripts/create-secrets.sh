#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Cria no cluster as Secrets que os manifestos esperam.
#
# As senhas NAO estao no Git: o Terraform as gerou e guardou no AWS Secrets
# Manager. Este script le de la e materializa no Kubernetes.
#
#   ./scripts/create-secrets.sh
#
# Em producao o caminho correto e o External Secrets Operator, que faz isto
# continuamente. Para a demonstracao, rodar uma vez basta.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."
export AWS_PAGER=""
TF="terraform/environments/dev"
REGION="${REGION:-us-east-1}"
command -v jq >/dev/null || { echo "ERRO: instale o jq."; exit 1; }

db_url() {
  aws secretsmanager get-secret-value --region "$REGION" \
    --secret-id "$(terraform -chdir="$TF" output -json rds_secret_names | jq -r --arg k "$1" '.[$k]')" \
    --query SecretString --output text | jq -r .DATABASE_URL
}

for s in auth flag targeting evaluation analytics; do
  kubectl create namespace "${s}-service" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done

echo ">> auth-secret (DATABASE_URL + MASTER_KEY)"
kubectl -n auth-service create secret generic auth-secret \
  --from-literal=DATABASE_URL="$(db_url auth)" \
  --from-literal=MASTER_KEY="$(openssl rand -hex 32)" \
  --dry-run=client -o yaml | kubectl apply -f -

for s in flag targeting; do
  echo ">> ${s}-secret (DATABASE_URL)"
  kubectl -n "${s}-service" create secret generic "${s}-secret" \
    --from-literal=DATABASE_URL="$(db_url "$s")" \
    --dry-run=client -o yaml | kubectl apply -f -
done

echo ">> evaluation-secret (SERVICE_API_KEY)"
kubectl -n evaluation-service create secret generic evaluation-secret \
  --from-literal=SERVICE_API_KEY="$(openssl rand -hex 32)" \
  --dry-run=client -o yaml | kubectl apply -f -

# analytics nao recebe Secret: o acesso dele a AWS vem do IRSA.
echo
echo "Pronto. Conferir:  kubectl get secrets -A | grep -- -secret"
