#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Preenche os marcadores <...> dos manifestos com os valores reais do
# Terraform. Substitui a tarefa manual de copiar endereco do console.
#
#   ./scripts/render-gitops.sh
#
# Depois rode `git diff` para conferir e commite. O ArgoCD aplica sozinho.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."
TF="terraform/environments/dev"
command -v jq >/dev/null || { echo "ERRO: instale o jq."; exit 1; }

out()  { terraform -chdir="$TF" output -raw "$1" 2>/dev/null; }
outj() { terraform -chdir="$TF" output -json "$1" 2>/dev/null; }

REGION=$(out aws_region 2>/dev/null || echo "us-east-1")
REDIS=$(out redis_url)
SQS=$(out sqs_queue_url)
[ -n "$REDIS" ] && [ -n "$SQS" ] || { echo "ERRO: infraestrutura nao aplicada? Rode terraform apply em $TF."; exit 1; }

ECR=$(outj ecr_repository_urls)
IRSA=$(outj irsa_role_arns)

echo ">> Preenchendo manifestos..."
for s in auth flag targeting evaluation analytics; do
  d="gitops/${s}-service"
  img=$(echo "$ECR" | jq -r --arg k "${s}-service" '.[$k]')
  # A tag 'latest' vale so para o primeiro deploy: depois o CI troca pela do commit.
  sed -i "s|<IMAGEM_ECR>|${img}:latest|g" "$d"/*.yaml
  sed -i "s|<AWS_REGION>|${REGION}|g"     "$d"/*.yaml
  sed -i "s|<AWS_SQS_URL>|${SQS}|g"       "$d"/*.yaml
  sed -i "s|<REDIS_URL>|${REDIS}|g"       "$d"/*.yaml
  echo "   ${s}-service  ->  ${img}"
done

for s in evaluation analytics; do
  arn=$(echo "$IRSA" | jq -r --arg k "$s" '.[$k]')
  sed -i "s|<IRSA_ROLE_ARN_$(echo $s | tr a-z A-Z)>|${arn}|g" "gitops/${s}-service"/*.yaml
  echo "   IRSA ${s}  ->  ${arn}"
done

echo
echo ">> Marcadores restantes (devem ser apenas o repoURL do ArgoCD):"
grep -rn "<[A-Z_]*>\|SUA-ORG" gitops/ || echo "   nenhum"
