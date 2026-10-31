#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# PROVISIONAMENTO COMPLETO — do zero ao sistema no ar.
#
# Encadeia, na ordem correta, tudo o que o docs/COMO-TESTAR.md ensina passo a
# passo. Cada etapa e idempotente: pode rodar de novo com seguranca se algo
# falhar no meio.
#
#   ./scripts/provision-all.sh                 # interativo
#   ./scripts/provision-all.sh --yes           # sem perguntar (cuidado)
#   ./scripts/provision-all.sh --skip-images   # nao faz build/push das imagens
#
# >>> ISTO GERA CUSTO NA AWS: ~US$ 0,32/hora (R$ 1,72). <<<
# Para desligar: ./scripts/destroy-all.sh
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."
export AWS_PAGER=""

TF_BOOT="terraform/bootstrap"
TF_DEV="terraform/environments/dev"
TF_ADDONS="terraform/environments/dev-addons"
REGION="${REGION:-us-east-1}"

ASSUME_YES=0; SKIP_IMAGES=0; SKIP_ADDONS=0; SKIP_ARGOCD=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y)      ASSUME_YES=1 ;;
    --skip-images) SKIP_IMAGES=1 ;;
    --skip-addons) SKIP_ADDONS=1 ;;
    --skip-argocd) SKIP_ARGOCD=1 ;;
    -h|--help)     sed -n '2,/^# ---.*-$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Opcao desconhecida: $arg" >&2; exit 1 ;;
  esac
done

STEP=0
step()  { STEP=$((STEP+1)); echo; echo "═══ [$STEP] $* ═══"; }
info()  { echo "    $*"; }
ok()    { echo "    ✓ $*"; }
die()   { echo; echo "    ✗ ERRO: $*" >&2; exit 1; }
tfo()   { terraform -chdir="$TF_DEV" output -raw "$1" 2>/dev/null || true; }

START=$(date +%s)

# ============================ 0. PRE-REQUISITOS ============================
step "Conferindo pre-requisitos"

for bin in terraform aws kubectl helm jq git; do
  command -v "$bin" >/dev/null || die "'$bin' nao encontrado. Veja o Passo 0 do docs/COMO-TESTAR.md"
done
ok "terraform, aws, kubectl, helm, jq, git presentes"

ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  || die "credenciais AWS nao configuradas. Rode: aws configure"
ok "conta AWS $ACCOUNT, regiao $REGION"

if [ "$SKIP_IMAGES" -eq 0 ] && ! docker info >/dev/null 2>&1; then
  info "docker indisponivel — as imagens nao serao construidas"
  SKIP_IMAGES=1
fi

# ============================ CONFIRMACAO ==================================
if [ "$ASSUME_YES" -eq 0 ]; then
  cat <<AVISO

┌──────────────────────────────────────────────────────────────┐
│  ISTO VAI CRIAR INFRAESTRUTURA REAL NA AWS                   │
│                                                              │
│  Conta: $ACCOUNT  ·  Regiao: $REGION
│  Custo: ~US\$ 0,32/hora  (~R\$ 1,72/hora)                      │
│  Tempo: ~30 minutos                                          │
│                                                              │
│  Para desligar depois:  ./scripts/destroy-all.sh             │
└──────────────────────────────────────────────────────────────┘
AVISO
  read -r -p "Digite 'provisionar' para continuar: " C
  [ "$C" = "provisionar" ] || { echo "Cancelado."; exit 1; }
fi

# ============================ 1. BOOTSTRAP =================================
step "Cofre do Terraform (bucket S3 do state)"

terraform -chdir="$TF_BOOT" init -input=false >/dev/null

# O state do bootstrap e LOCAL (nao vai para o Git, por design). Se ele se
# perder — maquina nova, repositorio reclonado — o Terraform nao sabe que o
# bucket ja existe e o apply morre com "BucketAlreadyExists".
# Nome do bucket de um bucket S3 e global: nao da para simplesmente criar
# outro. A saida e importar o que ja existe para dentro do state.
WANT_BUCKET=$(sed -n 's/.*bucket *= *"\([^"]*\)".*/\1/p' "$TF_DEV/backend.tf" | head -1)

if ! terraform -chdir="$TF_BOOT" state list 2>/dev/null | grep -q '^aws_s3_bucket.tfstate$'; then
  if aws s3api head-bucket --bucket "$WANT_BUCKET" >/dev/null 2>&1; then
    info "bucket $WANT_BUCKET ja existe mas nao esta no state — importando"
    for r in aws_s3_bucket.tfstate \
             aws_s3_bucket_versioning.tfstate \
             aws_s3_bucket_server_side_encryption_configuration.tfstate \
             aws_s3_bucket_public_access_block.tfstate \
             aws_s3_bucket_lifecycle_configuration.tfstate; do
      terraform -chdir="$TF_BOOT" import -input=false "$r" "$WANT_BUCKET" >/dev/null 2>&1 \
        || info "  (nao importou $r — segue; o apply reconcilia)"
    done
    ok "bucket existente adotado pelo Terraform"
  fi
fi

terraform -chdir="$TF_BOOT" apply -auto-approve -input=false >/dev/null
BUCKET=$(terraform -chdir="$TF_BOOT" output -raw bucket_name)
ok "bucket: $BUCKET"

# O backend.tf tem o nome do bucket fixo. Se nao bater, o init falha com uma
# mensagem obscura — melhor detectar aqui e dizer exatamente o que corrigir.
BACKEND_BUCKET=$(sed -n 's/.*bucket *= *"\([^"]*\)".*/\1/p' "$TF_DEV/backend.tf" | head -1)
if [ "$BUCKET" != "$BACKEND_BUCKET" ]; then
  die "o bucket criado ($BUCKET) difere do declarado em $TF_DEV/backend.tf ($BACKEND_BUCKET).
       Corrija o nome nos dois backend.tf (dev e dev-addons) e rode de novo."
fi
ok "backend.tf confere"

# ============================ 2. INFRAESTRUTURA ============================
step "Infraestrutura na AWS (~20 min — nao interrompa)"

terraform -chdir="$TF_DEV" init -input=false >/dev/null
info "calculando o plano..."
terraform -chdir="$TF_DEV" plan -out=.tfplan -input=false -no-color \
  | tail -3 | sed 's/^/    /'
info "aplicando..."
terraform -chdir="$TF_DEV" apply -input=false .tfplan | tail -2 | sed 's/^/    /'
rm -f "$TF_DEV/.tfplan"

CLUSTER=$(tfo cluster_name)
[ -n "$CLUSTER" ] || die "cluster nao criado"
ok "cluster: $CLUSTER"

# ============================ 3. ACESSO AO CLUSTER =========================
step "Conectando o kubectl"

aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null
info "aguardando os nos ficarem Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=600s >/dev/null \
  || die "os nos nao ficaram Ready. Sem NAT Gateway isso nunca acontece — veja docs/COMO-TESTAR.md"
ok "$(kubectl get nodes --no-headers | wc -l) nos Ready"

# ============================ 4. ADDONS ====================================
if [ "$SKIP_ADDONS" -eq 1 ]; then
  step "Addons do cluster — PULADO (--skip-addons)"
else
  step "Nginx Ingress, Metrics Server, ArgoCD e KEDA (~5 min)"
  terraform -chdir="$TF_ADDONS" init -input=false >/dev/null
  terraform -chdir="$TF_ADDONS" apply -auto-approve -input=false | tail -2 | sed 's/^/    /'
  ok "addons instalados"
fi

# ============================ 5. IMAGENS ===================================
if [ "$SKIP_IMAGES" -eq 1 ]; then
  step "Imagens Docker — PULADO"
  info "sem imagens no ECR os pods ficam em ImagePullBackOff."
  info "rode depois:  ./05-build-push-ecr.sh ."
else
  step "Construindo e publicando as 5 imagens no ECR"
  ./05-build-push-ecr.sh . | tail -4 | sed 's/^/    /'
  ok "imagens publicadas"
fi

# ============================ 6. SEGREDOS ==================================
step "Criando as Secrets no cluster"
./scripts/create-secrets.sh >/dev/null
ok "$(kubectl get secrets -A --no-headers 2>/dev/null | grep -c -- '-secret') Secrets criadas"

# ============================ 7. MANIFESTOS ================================
step "Preenchendo os enderecos nos manifestos"
./scripts/render-gitops.sh | grep -E "^   " | sed 's/^/    /' || true
ok "manifestos preenchidos"

# ============================ 8. GITOPS ====================================
step "Publicando os manifestos e ligando o ArgoCD"

if ! git diff --quiet -- gitops/ 2>/dev/null; then
  git add gitops/
  git -c user.email="$(git config user.email || echo infra@local)" \
      -c user.name="$(git config user.name || echo infra)" \
      commit -q -m "chore: enderecos da infraestrutura provisionada"
  ok "alteracoes commitadas"
fi

REMOTE=$(git remote get-url origin 2>/dev/null || true)
PLACEHOLDER=$(grep -rl "SUA-ORG" gitops/argocd/ 2>/dev/null | head -1 || true)

if [ "$SKIP_ARGOCD" -eq 1 ]; then
  info "ArgoCD — PULADO (--skip-argocd)"
elif [ -n "$PLACEHOLDER" ]; then
  info "ATENCAO: gitops/argocd/ ainda aponta para 'SUA-ORG'."
  info "O ArgoCD le de uma URL publica, nao do seu disco. Ajuste e aplique:"
  info "  sed -i 's|https://github.com/SUA-ORG/tech-challenge.git|SUA-URL|' gitops/argocd/*.yaml"
  info "  git push && kubectl apply -f gitops/argocd/"
elif [ -z "$REMOTE" ]; then
  info "ATENCAO: o repositorio nao tem remoto. Publique antes de ligar o ArgoCD:"
  info "  gh repo create SUA-ORG/tech-challenge --private --source=. --push"
else
  git push -q 2>/dev/null && ok "enviado para $REMOTE" || info "push falhou — envie manualmente"
  kubectl apply -f gitops/argocd/ >/dev/null
  ok "5 Applications registradas no ArgoCD"
fi

# ============================ RESUMO =======================================
MIN=$(( ($(date +%s) - START) / 60 ))
cat <<FIM

═══════════════════════════════════════════════════════════════
  PRONTO em ${MIN} minutos
═══════════════════════════════════════════════════════════════

  Cluster ......... $CLUSTER
  Redis ........... $(tfo redis_url)
  Fila SQS ........ $(tfo sqs_queue_url)
  DynamoDB ........ $(tfo dynamodb_table_name)

  Endereco publico (pode levar ~2 min para aparecer):
    kubectl -n ingress-nginx get svc ingress-nginx-controller \\
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

  Painel do ArgoCD:
    kubectl -n argocd get secret argocd-initial-admin-secret \\
      -o jsonpath="{.data.password}" | base64 -d
    kubectl -n argocd port-forward svc/argocd-server 8080:80

  Conferir:
    kubectl get pods -A | grep -- -service
    kubectl get applications -n argocd

  ⚠  ESTA CORRENDO CUSTO: ~US\$ 0,32/hora (~R\$ 1,72/hora)
     Para desligar:  ./scripts/destroy-all.sh
     Depois confira: ./scripts/check-costs.sh
═══════════════════════════════════════════════════════════════
FIM
