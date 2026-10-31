#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Lista tudo que esta de pe e cobrando por hora.
#
# Rode SEMPRE depois de um destroy. O destroy pode terminar com sucesso e
# ainda assim deixar residuo: Load Balancer criado pelo Kubernetes, Elastic
# IP desassociado (a AWS cobra justamente por estar ocioso), snapshot de RDS.
# ---------------------------------------------------------------------------
set -uo pipefail
export AWS_PAGER=""
REGION="${REGION:-us-east-1}"

echo "=========== RECURSOS ATIVOS EM ${REGION} ==========="
probe() {
  local label="$1"; shift
  local out
  out=$("$@" 2>/dev/null)
  if [ -n "${out//[[:space:]]/}" ] && [ "$out" != "None" ]; then
    echo "  [COBRANDO] $label:"
    echo "$out" | sed 's/^/      /'
  else
    echo "  [ok] $label: nada"
  fi
}

probe "Clusters EKS (~US\$ 0,10/h cada)" \
  aws eks list-clusters --region "$REGION" --query 'clusters' --output text
probe "Instancias EC2 / nos" \
  aws ec2 describe-instances --region "$REGION" --filters Name=instance-state-name,Values=running,pending \
    --query 'Reservations[].Instances[].[InstanceId,InstanceType]' --output text
probe "Instancias RDS" \
  aws rds describe-db-instances --region "$REGION" --query 'DBInstances[].DBInstanceIdentifier' --output text
probe "Clusters ElastiCache" \
  aws elasticache describe-cache-clusters --region "$REGION" --query 'CacheClusters[].CacheClusterId' --output text
probe "NAT Gateways (~US\$ 0,045/h cada)" \
  aws ec2 describe-nat-gateways --region "$REGION" \
    --filter Name=state,Values=available,pending --query 'NatGateways[].NatGatewayId' --output text
probe "Elastic IPs (cobrados mesmo ociosos)" \
  aws ec2 describe-addresses --region "$REGION" --query 'Addresses[].PublicIp' --output text
probe "Load Balancers" \
  aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[].LoadBalancerName' --output text
probe "Load Balancers classicos" \
  aws elb describe-load-balancers --region "$REGION" --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text
probe "Snapshots de RDS" \
  aws rds describe-db-snapshots --region "$REGION" --snapshot-type manual --query 'DBSnapshots[].DBSnapshotIdentifier' --output text
probe "Volumes EBS soltos" \
  aws ec2 describe-volumes --region "$REGION" --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text

echo
echo "Presentes por design, custo despreziv el (nao precisam sair):"
echo "  - Bucket S3 do tfstate       ~US\$ 0,00"
echo "  - Tabela DynamoDB on-demand   US\$ 0,00 sem trafego"
echo "  - Repositorios ECR            US\$ 0,10/GB/mes"
echo "  - Secrets Manager             US\$ 0,40/secret/mes (3 secrets)"
echo "==================================================="
