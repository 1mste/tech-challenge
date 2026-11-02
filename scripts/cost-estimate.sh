#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Estimativa de custos consultando a API de precos da AWS, ao vivo.
#
# Serve para o print exigido no Relatorio de Entrega. Os valores NAO sao
# digitados a mao: cada linha e buscada em tempo real na AWS Price List API,
# e o rodape mostra data, regiao e origem para quem for conferir.
#
#   ./scripts/cost-estimate.sh            # em dolar
#   BRL=5.30 ./scripts/cost-estimate.sh   # acrescenta coluna em real
# ---------------------------------------------------------------------------
set -uo pipefail
export AWS_PAGER=""
REGION="${REGION:-us-east-1}"
LOC="US East (N. Virginia)"
BRL="${BRL:-5.30}"
HORAS_MES=730

command -v jq >/dev/null || { echo "ERRO: instale o jq." >&2; exit 1; }

# preco <service-code> <json-de-filtros>  -> imprime o preco unitario em USD
preco() {
  local svc="$1" filtros="$2"
  local body
  body=$(python3 -c "
import json,sys
f=json.loads(sys.argv[2])
print(json.dumps({'ServiceCode':sys.argv[1],
  'Filters':[{'Type':'TERM_MATCH','Field':k,'Value':v} for k,v in f.items()],
  'MaxResults':1}))" "$svc" "$filtros")
  aws pricing get-products --region us-east-1 --service-code "$svc" \
      --cli-input-json "$body" --query 'PriceList[0]' --output text 2>/dev/null \
  | python3 -c "
import json,sys
try:
    d=json.loads(sys.stdin.read())
    for t in d['terms']['OnDemand'].values():
        for dim in t['priceDimensions'].values():
            print(dim['pricePerUnit']['USD']); sys.exit()
except Exception: pass
print('')"
}

TOTAL_H=0
LINHAS=()

# linha <descricao> <config> <qtd> <preco-unit-hora>
linha() {
  local desc="$1" cfg="$2" qtd="$3" unit="$4"
  if [ -z "$unit" ]; then
    LINHAS+=("$(printf '  │ %-22s │ %-33s │ %3s │ %8s │ %9s │' "$desc" "$cfg" "$qtd" "n/d" "n/d")")
    return
  fi
  local h m
  h=$(python3 -c "print(f'{float('$unit')*$qtd:.4f}')")
  m=$(python3 -c "print(f'{float('$h')*$HORAS_MES:.2f}')")
  TOTAL_H=$(python3 -c "print(f'{$TOTAL_H + float('$h'):.4f}')")
  LINHAS+=("$(printf '  │ %-22s │ %-33s │ %3s │ %8s │ %9s │' "$desc" "$cfg" "$qtd" "$h" "$m")")
}

echo "consultando a API de precos da AWS..." >&2

P_EKS=$(preco AmazonEKS '{"usagetype":"USE1-AmazonEKS-Hours:perCluster"}')
P_EC2=$(preco AmazonEC2 "{\"instanceType\":\"t3.medium\",\"location\":\"$LOC\",\"operatingSystem\":\"Linux\",\"tenancy\":\"Shared\",\"preInstalledSw\":\"NA\",\"capacitystatus\":\"Used\"}")
P_RDS=$(preco AmazonRDS "{\"usagetype\":\"InstanceUsage:db.t3.micro\",\"location\":\"$LOC\",\"databaseEngine\":\"PostgreSQL\",\"deploymentOption\":\"Single-AZ\"}")
P_NAT=$(preco AmazonEC2 "{\"location\":\"$LOC\",\"groupDescription\":\"Hourly charge for NAT Gateways\"}")
P_NLB=$(preco AWSELB "{\"location\":\"$LOC\",\"usagetype\":\"LoadBalancerUsage\",\"operation\":\"LoadBalancing:Network\"}")
P_CACHE=$(preco AmazonElastiCache "{\"usagetype\":\"NodeUsage:cache.t3.micro\",\"location\":\"$LOC\",\"cacheEngine\":\"Redis\"}")
P_EBS_GB=$(preco AmazonEC2 "{\"location\":\"$LOC\",\"volumeApiName\":\"gp3\",\"productFamily\":\"Storage\"}")
# EBS e cobrado por GB-mes; converte para hora para somar na mesma unidade
P_EBS_H=""
[ -n "$P_EBS_GB" ] && P_EBS_H=$(python3 -c "print(float('$P_EBS_GB')*40/$HORAS_MES)")

linha "Amazon EKS"          "control plane"                      1 "$P_EKS"
linha "Amazon EC2"          "t3.medium, Linux, sob demanda"      2 "$P_EC2"
linha "Amazon RDS"          "db.t3.micro PostgreSQL, Single-AZ"  3 "$P_RDS"
linha "VPC NAT Gateway"     "1 por VPC (single_nat_gateway)"     1 "$P_NAT"
linha "Elastic Load Bal."   "Network Load Balancer"              1 "$P_NLB"
linha "Amazon ElastiCache"  "cache.t3.micro, Redis"              1 "$P_CACHE"
linha "Amazon EBS"          "gp3, 40 GiB (2 x 20)"               1 "$P_EBS_H"

TOTAL_M=$(python3 -c "print(f'{$TOTAL_H*$HORAS_MES:.2f}')")
T_BRL_H=$(python3 -c "print(f'{$TOTAL_H*$BRL:.2f}')")
T_BRL_M=$(python3 -c "print(f'{$TOTAL_M*$BRL:.2f}')")
TOPO="  ┌────────────────────────┬───────────────────────────────────┬─────┬──────────┬───────────┐"
MEIO="  ├────────────────────────┼───────────────────────────────────┼─────┼──────────┼───────────┤"
BASE="  └────────────────────────┴───────────────────────────────────┴─────┴──────────┴───────────┘"
BRLF=$(python3 -c "print(f'{float(\"$BRL\"):.2f}'.replace('.',','))")

echo
echo "  ╔═══════════════════════════════════════════════════════════════════════════════════════╗"
echo "  ║  ToggleMaster — Tech Challenge Fase 3                                                 ║"
echo "  ║  ESTIMATIVA DE CUSTOS DA INFRAESTRUTURA AWS                                           ║"
echo "  ╚═══════════════════════════════════════════════════════════════════════════════════════╝"
echo
echo "$TOPO"
printf '  │ %-22s │ %-33s │ %3s │ %8s │ %9s │\n' "SERVICO" "CONFIGURACAO" "QTD" "US$/HORA" "US$/MES"
echo "$MEIO"
printf '%s\n' "${LINHAS[@]}"
echo "$MEIO"
printf '  │ %-22s │ %-33s │ %3s │ %8s │ %9s │\n' "TOTAL" "" "" "$TOTAL_H" "$TOTAL_M"
echo "$BASE"
echo
printf '  Em reais (US$ 1,00 = R$ %s):   R$ %s/hora   ·   R$ %s/mes\n' "$BRLF" "$T_BRL_H" "$T_BRL_M"
echo
echo "  ┌─ CUSTO REAL DA ENTREGA ─────────────────────────────────────────┐"
for par in "Subir, testar e destruir:2" "Um dia de trabalho:8" "Esquecido um fim de semana:60"; do
  d="${par%%:*}"; hh="${par##*:}"
  u=$(python3 -c "print(f'{$TOTAL_H*$hh:.2f}')"); r=$(python3 -c "print(f'{$TOTAL_H*$hh*$BRL:.2f}')")
  printf '  │  %-28s %3sh   US$ %6s   R$ %8s  │\n' "$d" "$hh" "$u" "$r"
done
echo "  └─────────────────────────────────────────────────────────────────┘"
echo
echo "  Nao entram no total (cobrados por uso, valor desprezivel):"
echo "    DynamoDB on-demand · SQS · ECR ~US\$ 0,30/mes · Secrets Manager US\$ 1,20/mes"
echo
echo "  Regiao ....... ${REGION} (${LOC})"
echo "  Precos ....... sob demanda, sem compromisso de uso"
echo "  Fonte ........ AWS Price List API (aws pricing get-products)"
echo "  Consultado ... $(date '+%d/%m/%Y as %H:%M %Z')"
echo "  Conta AWS .... $(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
echo
