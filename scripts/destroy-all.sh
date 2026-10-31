#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# DESTRUIÇÃO COMPLETA — zera o que gera custo.
#
# A ORDEM IMPORTA:
#
#   1. Stack de addons. O Nginx Ingress criou um NLB que o Terraform da
#      infra NÃO conhece. Se ele continuar de pé, dois problemas: o NLB
#      segue custando, e a VPC não é apagada (ENIs presas), travando o
#      destroy no timeout depois de ~20 minutos.
#
#   2. Stack de infra. EKS, RDS, Redis, NAT, VPC.
#
#   3. O bucket de state (bootstrap) NÃO é destruído aqui. Ele custa
#      centavos e guarda o histórico. Para removê-lo, veja o README.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

ADDONS_DIR="$(pwd)/terraform/environments/dev-addons"

echo "Isto vai DESTRUIR toda a infraestrutura do ToggleMaster na conta ${ACCOUNT_ID}."
read -r -p "Digite 'destruir' para confirmar: " CONFIRM
[ "$CONFIRM" = "destruir" ] || { echo "Cancelado."; exit 1; }

# --- 1. Addons (derruba o NLB) ---
if [ -d "$ADDONS_DIR/.terraform" ]; then
  echo ">> [1/3] Removendo addons (Nginx/ArgoCD/Metrics Server) e o NLB..."
  terraform -chdir="$ADDONS_DIR" destroy -auto-approve || \
    echo "   AVISO: destroy dos addons falhou; verifique o NLB manualmente antes de seguir."
else
  echo ">> [1/3] Stack de addons nunca foi inicializada, pulando."
fi

# --- 2. Rede de segurança: sobrou algum Load Balancer criado pelo Kubernetes? ---
echo ">> [2/3] Procurando Load Balancers órfãos NA VPC DESTE PROJETO..."
# Filtrar pela VPC (e não pelo nome) é o que impede apagar um Load Balancer
# de outro projeto que por acaso tenha nome parecido.
VPC_ID=$(terraform -chdir="$TF_DIR" output -raw vpc_id 2>/dev/null || true)
if [ -z "${VPC_ID:-}" ]; then
  echo "   VPC não encontrada no state; pulando esta verificação."
  ORPHANS=""
else
  ORPHANS=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?VpcId=='${VPC_ID}'].LoadBalancerArn" \
    --output text 2>/dev/null || true)
fi
if [ -n "${ORPHANS//[[:space:]]/}" ]; then
  echo "   Encontrados. Removendo para liberar a VPC:"
  for arn in $ORPHANS; do
    echo "     - $arn"
    aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$arn" || true
  done
  echo "   Aguardando 60s a liberação das interfaces de rede..."
  sleep 60
else
  echo "   Nenhum."
fi

# --- 2b. ENIs órfãs do VPC CNI ---
#
# O CNI do EKS cria ENIs para os pods e nem sempre as remove ao deletar o
# node group. Elas ficam em status "available" (desanexadas, sem custo), mas
# SEGURAM a subnet: o destroy fica minutos em "Still destroying..." numa
# subnet e só falha no timeout. Removê-las antes destrava na hora.
if [ -n "${VPC_ID:-}" ]; then
  echo ">> [2b] Procurando ENIs órfãs deixadas pelo VPC CNI..."
  ENIS=$(aws ec2 describe-network-interfaces --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=status,Values=available" \
    --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null || true)
  if [ -n "${ENIS//[[:space:]]/}" ]; then
    for eni in $ENIS; do
      echo "   removendo $eni"
      aws ec2 delete-network-interface --region "$REGION" --network-interface-id "$eni" || true
    done
  else
    echo "   Nenhuma."
  fi
fi

# --- 3. Infraestrutura ---
echo ">> [3/3] Destruindo a infraestrutura (EKS, RDS, Redis, NAT, VPC)..."
echo "   Isso leva ~20 minutos. Não interrompa."
terraform -chdir="$TF_DIR" destroy -auto-approve

echo
echo "Concluído. Rodando a verificação final de custos..."
exec "$(dirname "$0")/check-costs.sh"
