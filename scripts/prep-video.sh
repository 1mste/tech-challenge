#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# PREPARACAO PARA GRAVAR O VIDEO DA FASE 3
#
# Executa os 5 passos anteriores a gravacao:
#   1. Publica o codigo no GitHub      (o ArgoCD le de la, nao do disco)
#   2. Cria a credencial do pipeline   (role OIDC + variavel AWS_ROLE_ARN)
#   3. Termina o provisionamento       (chama o provision-all.sh)
#   4. Confere que esta tudo verde
#   5. Ensaia a cena de falha do pipeline, sem sujar o repositorio
#
#   ./scripts/prep-video.sh
#   ./scripts/prep-video.sh --yes              # sem perguntar
#   ./scripts/prep-video.sh --skip-provision   # se a infra ja estiver pronta
#
# >>> O passo 3 GERA CUSTO: ~US$ 0,33/hora. Desligue com destroy-all.sh. <<<
# ---------------------------------------------------------------------------
set -uo pipefail
cd "$(dirname "$0")/.."
export AWS_PAGER=""
REGION="${REGION:-us-east-1}"

SIM=0; PULA_PUSH=0; PULA_PROV=0
for a in "$@"; do case "$a" in
  --yes|-y)         SIM=1 ;;
  --skip-push)      PULA_PUSH=1 ;;
  --skip-provision) PULA_PROV=1 ;;
  -h|--help)        sed -n '2,/^# ---.*-$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
  *) echo "Opcao desconhecida: $a" >&2; exit 1 ;;
esac; done

N=0
passo() { N=$((N+1)); echo; echo "═══ [$N] $* ═══"; }
info()  { echo "    $*"; }
ok()    { echo "    ✓ $*"; }
nok()   { echo "    ✗ $*"; }
confirma() {
  [ "$SIM" = "1" ] && return 0
  read -r -p "    $1 [s/N] " R; [ "${R,,}" = "s" ]
}

FALHAS=0

# ============================ 1. PUBLICAR ==================================
passo "Publicar o codigo no GitHub"

if [ "$PULA_PUSH" = "1" ]; then
  info "pulado (--skip-push)"
elif ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files -o --exclude-standard)" ]; then
  echo
  git status --short | sed 's/^/      /'
  echo
  if confirma "Commitar e publicar estas alteracoes?"; then
    git add -A
    git commit -q -m "fix: IRSA do KEDA e pipeline DevSecOps completo" && ok "commitado"
  else
    info "mantido como esta — lembre que o ArgoCD le do GitHub"
  fi
else
  ok "nada pendente"
fi

if [ "$PULA_PUSH" != "1" ] && [ "$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)" != "0" ]; then
  if git push -q 2>/dev/null; then
    ok "enviado para $(git remote get-url origin)"
  else
    nok "push falhou — autentique com 'gh auth login' ou troque o remoto para SSH"
    FALHAS=$((FALHAS+1))
  fi
else
  ok "remoto atualizado"
fi

# ============================ 2. CREDENCIAL ================================
passo "Credencial do pipeline (OIDC)"

REPO=$(git remote get-url origin 2>/dev/null | sed -E 's|.*github\.com[:/]||; s|\.git$||')
if [ -z "$REPO" ]; then
  nok "sem remoto no GitHub; nao da para criar a role"
  FALHAS=$((FALHAS+1))
else
  info "repositorio: $REPO"

  # Com GITHUB_TOKEN no ambiente, o proprio Terraform cadastra a variavel
  # AWS_ROLE_ARN no repositorio — nada de copiar e colar no navegador.
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    GH_VAR="true"; info "GITHUB_TOKEN presente: a variavel sera cadastrada pelo Terraform"
  else
    GH_VAR="false"
    info "sem GITHUB_TOKEN: a role sera criada, mas a variavel ficara por sua conta"
    info "  para automatizar:  export GITHUB_TOKEN=... (escopo repo)"
  fi

  # A saida NAO e suprimida: silenciar o apply foi o que escondeu a falha
  # da criacao da variavel e fez o script reportar sucesso indevidamente.
  if ! terraform -chdir=terraform/environments/dev apply -auto-approve -input=false \
       -var="github_repositories=[\"$REPO\"]" \
       -var="manage_github_variable=$GH_VAR" 2>&1 | tail -6 | sed 's/^/      /'; then
    nok "o terraform apply falhou (veja acima)"
    FALHAS=$((FALHAS+1))
  fi

  ARN=$(terraform -chdir=terraform/environments/dev output -raw github_actions_role_arn 2>/dev/null)

  if [ -z "$ARN" ]; then
    nok "a role nao foi criada"
    FALHAS=$((FALHAS+1))
  else
    ok "role: $ARN"
    # Confere no STATE em vez de confiar na intencao: antes bastava o token
    # existir para o script declarar sucesso, mesmo sem a variavel existir.
    if [ "$GH_VAR" = "true" ] && terraform -chdir=terraform/environments/dev state list 2>/dev/null \
         | grep -q "^github_actions_variable.aws_role_arn$"; then
      ok "variavel AWS_ROLE_ARN cadastrada no repositorio"
    elif [ "$GH_VAR" = "true" ]; then
      nok "a variavel NAO foi criada — o pipeline vai falhar em 'role-to-assume' vazio"
      info "  cadastre manualmente: Settings > Secrets and variables > Actions > Variables"
      info "  Nome: AWS_ROLE_ARN   Valor: $ARN"
      FALHAS=$((FALHAS+1))
    else
      info "CADASTRE MANUALMENTE:"
      info "  GitHub > Settings > Secrets and variables > Actions > Variables"
      info "  Nome: AWS_ROLE_ARN   Valor: $ARN"
    fi
  fi
fi

# ============================ 3. PROVISIONAR ===============================
passo "Terminar o provisionamento"

if [ "$PULA_PROV" = "1" ]; then
  info "pulado (--skip-provision)"
else
  info "chamando provision-all.sh (idempotente; o que ja existe vira no-op)"
  ./scripts/provision-all.sh --yes | grep -E "═══|✓|✗|ATENCAO" | sed 's/^/    /'
fi

# ============================ 4. CONFERIR ==================================
passo "Conferindo o ambiente"

aws eks update-kubeconfig --region "$REGION" --name togglemaster-dev-eks >/dev/null 2>&1

checa() { # checa <rotulo> <esperado> <valor>
  if [ "$2" = "$3" ]; then ok "$1: $3"; else nok "$1: $3 (esperado $2)"; FALHAS=$((FALHAS+1)); fi
}

checa "nos Ready" "2" "$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ')"
checa "Applications Synced" "5" "$(kubectl get applications -n argocd --no-headers 2>/dev/null | grep -c 'Synced')"
# "9 ou mais", nao exatamente 9: com o KEDA ativo o analytics escala ate 10,
# e uma comparacao exata acusaria falha justamente quando tudo funciona.
PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -- '-service' | grep -c 'Running')
if [ "${PODS:-0}" -ge 9 ]; then
  ok "pods de aplicacao Running: $PODS"
else
  nok "pods de aplicacao Running: $PODS (esperado 9 ou mais)"; FALHAS=$((FALHAS+1))
fi

READY=$(kubectl get scaledobject -n analytics-service -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [ "$READY" = "True" ]; then
  ok "KEDA lendo a fila (ScaledObject Ready)"
else
  nok "KEDA NAO esta lendo a fila (Ready=$READY) — a cena de escala nao vai funcionar"
  info "  kubectl -n keda logs deploy/keda-operator --tail=20"
  FALHAS=$((FALHAS+1))
fi

URL=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -n "$URL" ]; then ok "endereco publico: $URL"; else nok "Load Balancer sem endereco ainda"; fi

# ============================ 5. ENSAIO ====================================
passo "Ensaio da cena de falha do pipeline"

# Pillow 8.0.0 tem 8 CVEs CRITICAL na base do Trivy. Verificado em 02/11/2026.
# requests==2.19.1 NAO serve: as falhas dele sao HIGH, e o gate exige CRITICAL.
DEP="${DEP_VULNERAVEL:-Pillow==8.0.0}"
if ! docker info >/dev/null 2>&1; then
  info "docker indisponivel — nao da para ensaiar aqui"
else
  TMP=$(mktemp -d); cp flag-service/requirements.txt "$TMP/" 2>/dev/null
  # printf com \n antes: varios requirements.txt nao terminam em quebra de
  # linha, e um ">>" simples colaria a dependencia na linha anterior — o
  # Trivy ignoraria a linha invalida e a cena do video nao aconteceria.
  printf '\n%s\n' "$DEP" >> "$TMP/requirements.txt"
  info "testando '$DEP' com o mesmo criterio do pipeline..."
  N_CRIT=$(docker run --rm -v "$TMP:/src" aquasec/trivy:latest \
            fs --severity CRITICAL --ignore-unfixed --quiet --format json /src 2>/dev/null \
          | python3 -c "import json,sys
try: d=json.load(sys.stdin); print(sum(len(r.get('Vulnerabilities') or []) for r in (d.get('Results') or [])))
except Exception: print(0)")
  rm -rf "$TMP"
  if [ "${N_CRIT:-0}" -gt 0 ]; then
    ok "$N_CRIT vulnerabilidade(s) CRITICAL — a cena vai funcionar"
  else
    nok "nenhuma CRITICAL em '$DEP' — o pipeline NAO vai reprovar"
    info "  tente outra: DEP_VULNERAVEL='PyYAML==5.3.1' ./scripts/prep-video.sh"
    FALHAS=$((FALHAS+1))
  fi
fi

# ============================ RESUMO =======================================
echo
if [ "$FALHAS" -eq 0 ]; then
  echo "═══════════════════════════════════════════════════════════════"
  echo "  TUDO PRONTO PARA GRAVAR"
else
  echo "═══════════════════════════════════════════════════════════════"
  echo "  $FALHAS ITEM(NS) PENDENTE(S) — resolva antes de gravar"
fi
cat <<FIM
═══════════════════════════════════════════════════════════════

  Cena 1 — IaC
    terraform -chdir=terraform/environments/dev plan
    console AWS: VPC, EKS, RDS, ElastiCache, SQS, DynamoDB

  Cena 2 — pipeline reprovando e depois passando
    printf '\\n%s\\n' '$DEP' >> flag-service/requirements.txt
    git commit -am "test: dependencia vulneravel" && git push
    (aba Actions: job vermelho + docker/update-gitops como Skipped)
    git revert HEAD && git push

  Cena 3 — pipeline atualizando o GitOps
    (log do job update-gitops + commit do github-actions[bot])

  Cena 4 — ArgoCD sincronizando
    kubectl -n argocd port-forward svc/argocd-server 8080:80
    kubectl -n argocd get secret argocd-initial-admin-secret \\
      -o jsonpath="{.data.password}" | base64 -d
    curl -i http://${URL:-<endereco>}/auth/health

  AO TERMINAR:
    ./scripts/destroy-all.sh && ./scripts/check-costs.sh

FIM
