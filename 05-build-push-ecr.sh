#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# PASSO 5 (opcional, roda quando o CÓDIGO das aplicações estiver presente) —
# Build + push das 5 imagens Docker para o ECR e geração de um artefato com as
# referências das imagens para o time colar nos manifestos Kubernetes.
#
# O código-fonte das aplicações NÃO vive neste repositório. Há duas formas de
# apontar onde ele está:
#
#   (A) Pasta única com as 5 subpastas de serviço (nomes iguais aos do ECR):
#       ./05-build-push-ecr.sh /caminho/para/apps
#       APPS_DIR=/caminho/para/apps ./05-build-push-ecr.sh
#
#   (B) Um repositório separado por serviço, via <PREFIXO>_DIR (tem prioridade
#       sobre APPS_DIR). Serviço que não tiver seu _DIR cai em $APPS_DIR/<serviço>:
#       AUTH_SERVICE_DIR=/repos/auth-service \
#       FLAG_SERVICE_DIR=/repos/flag-service-main \
#       TARGETING_SERVICE_DIR=/repos/targeting-service \
#       EVALUATION_SERVICE_DIR=/repos/evaluation-service \
#       ANALYTICS_SERVICE_DIR=/repos/analytics-service \
#       ./05-build-push-ecr.sh
#
# Variáveis opcionais:
#   IMAGE_TAG=algumatag   -> força a MESMA tag em todos os serviços.
#                            (padrão: git short SHA de CADA repo; senão timestamp)
#
# As imagens são construídas para linux/amd64 (os nós são t3.medium / x86_64).
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"
source ./env.sh

# converte "auth-service" -> "AUTH_SERVICE"
svc_env_prefix() { echo "$1" | tr '[:lower:]-' '[:upper:]_'; }

# --------------------- 1. Resolver origem do código ------------------------
# APPS_DIR agora é OPCIONAL: só é obrigatório para os serviços que não tiverem
# um <PREFIXO>_DIR próprio.
APPS_DIR="${1:-${APPS_DIR:-}}"
if [ -n "$APPS_DIR" ]; then
  if [ ! -d "$APPS_DIR" ]; then
    echo "ERRO: a pasta APPS_DIR '$APPS_DIR' não existe." >&2
    exit 1
  fi
  APPS_DIR="$(cd "$APPS_DIR" && pwd)"   # normaliza para caminho absoluto
fi

# Resolve o diretório de código de um serviço:
#   1) <PREFIXO>_DIR (ex.: AUTH_SERVICE_DIR)  -- tem prioridade
#   2) $APPS_DIR/<serviço>                     -- fallback
resolve_dir_for() {
  local repo="$1"
  local var; var="$(svc_env_prefix "$repo")_DIR"
  local d="${!var:-}"
  if [ -z "$d" ] && [ -n "$APPS_DIR" ]; then
    d="$APPS_DIR/$repo"
  fi
  echo "$d"
}

# --------------------------- Validações de config --------------------------
if [ -z "${ACCOUNT_ID:-}" ] || [ "$ACCOUNT_ID" = "None" ]; then
  echo "ERRO: ACCOUNT_ID vazio. As credenciais AWS estão configuradas? (aws configure)" >&2
  exit 1
fi
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# --------------------------- 2. Definir a TAG ------------------------------
# Timestamp único desta execução, usado como fallback quando um repo não é git.
RUN_TS="$(date +%Y%m%d-%H%M%S)"

# Tag de um serviço: IMAGE_TAG (global) > git short SHA do repo > timestamp.
resolve_tag_for() {
  local dir="$1"
  if [ -n "${IMAGE_TAG:-}" ]; then echo "$IMAGE_TAG"; return; fi
  if git -C "$dir" rev-parse --short HEAD >/dev/null 2>&1; then
    git -C "$dir" rev-parse --short HEAD; return
  fi
  echo "$RUN_TS"
}

echo ">> Registry : $REGISTRY"
[ -n "$APPS_DIR" ] && echo ">> APPS_DIR : $APPS_DIR (fallback)"
if [ -n "${IMAGE_TAG:-}" ]; then
  echo ">> TAG      : $IMAGE_TAG (forçada via IMAGE_TAG, igual em todos)"
else
  echo ">> TAG      : git short SHA de cada repo (fallback: timestamp $RUN_TS)"
fi

# --------------------- Detectar buildx (preferível) ------------------------
USE_BUILDX=0
if docker buildx version >/dev/null 2>&1; then
  USE_BUILDX=1
  echo ">> buildx disponível: usando 'docker buildx build --platform linux/amd64 --push'"
else
  echo ">> buildx indisponível: usando 'docker build --platform linux/amd64' + push"
fi

# --------------------------- 3. Login no ECR -------------------------------
echo ">> Fazendo login no ECR..."
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

# ---------- Acumuladores para o artefato (paralelos por índice) ------------
declare -a A_SVC A_REPO A_REF A_TAG A_DIGEST

# --------------------------- 4. Loop de build ------------------------------
for repo in "${ECR_REPOS[@]}"; do
  echo ""
  echo "==================== $repo ===================="
  CTX="$(resolve_dir_for "$repo")"

  if [ -z "$CTX" ]; then
    echo "ERRO: não sei onde está o código de '$repo'." >&2
    echo "      Defina $(svc_env_prefix "$repo")_DIR=<caminho> ou passe APPS_DIR com a subpasta '$repo/'." >&2
    exit 1
  fi
  if [ ! -d "$CTX" ]; then
    echo "ERRO: a pasta de '$repo' não existe: '$CTX'." >&2
    echo "      O código da aplicação precisa estar presente antes do build." >&2
    exit 1
  fi
  CTX="$(cd "$CTX" && pwd)"

  # Linux diferencia maiúsculas: os serviços deste repositório trazem
  # 'dockerfile' minúsculo, mas outros projetos usam 'Dockerfile'.
  # Aceita as duas grafias em vez de impor uma.
  DOCKERFILE=""
  for cand in Dockerfile dockerfile Containerfile; do
    if [ -f "$CTX/$cand" ]; then DOCKERFILE="$CTX/$cand"; break; fi
  done

  if [ -z "$DOCKERFILE" ]; then
    echo "ERRO: nenhum Dockerfile em '$CTX/'." >&2
    echo "      Procurei por: Dockerfile, dockerfile, Containerfile." >&2
    echo "      O código da aplicação de '$repo' precisa estar presente (pasta vazia?)." >&2
    exit 1
  fi

  # Repositório ECR precisa existir (criado pelo 02-aws-resources.sh).
  if ! aws ecr describe-repositories --region "$REGION" \
        --repository-names "$repo" >/dev/null 2>&1; then
    echo "ERRO: repositório ECR '$repo' não existe." >&2
    echo "      Os repositórios ECR são criados pelo Terraform. Rode:" >&2
    echo "        terraform -chdir=terraform/environments/dev apply" >&2
    exit 1
  fi

  TAG="$(resolve_tag_for "$CTX")"
  REF_TAG="${REGISTRY}/${repo}:${TAG}"
  REF_LATEST="${REGISTRY}/${repo}:latest"

  echo ">> Código  : $CTX"
  echo ">> Tag     : $TAG"
  echo ">> Build (linux/amd64) e push: $repo"
  if [ "$USE_BUILDX" -eq 1 ]; then
    docker buildx build --platform linux/amd64 \
      -t "$REF_TAG" -t "$REF_LATEST" \
      --push "$CTX"
  else
    docker build --platform linux/amd64 \
      -t "$REF_TAG" -t "$REF_LATEST" "$CTX"
    docker push "$REF_TAG"
    docker push "$REF_LATEST"
  fi

  # Captura o digest para permitir pin imutável (image@sha256:...).
  DIGEST="$(aws ecr describe-images --region "$REGION" \
    --repository-name "$repo" \
    --image-ids imageTag="$TAG" \
    --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || echo "")"
  if [ -n "$DIGEST" ] && [ "$DIGEST" != "None" ]; then
    echo "   OK -> $REF_TAG"
    echo "   digest: $DIGEST"
  else
    echo "   OK -> $REF_TAG (não foi possível ler o digest)"
    DIGEST="(indisponível)"
  fi

  A_SVC+=("$repo")
  A_REPO+=("$repo")
  A_REF+=("$REF_TAG")
  A_TAG+=("$TAG")
  A_DIGEST+=("$DIGEST")
done

# --------------------------- 5. Gerar artefatos ----------------------------
mkdir -p docs

# Rótulo de tag para o cabeçalho: mostra a tag só se for igual em todos.
ALL_TAGS_EQUAL=1
FIRST_TAG="${A_TAG[0]}"
for t in "${A_TAG[@]}"; do [ "$t" = "$FIRST_TAG" ] || ALL_TAGS_EQUAL=0; done
if [ "$ALL_TAGS_EQUAL" -eq 1 ]; then
  TAG_LABEL="\`$FIRST_TAG\`"
else
  TAG_LABEL="por serviço (git SHA de cada repo — ver coluna Tag)"
fi

# ---- docs/images.env (legível por máquina) ----
{
  echo "# Gerado por 05-build-push-ecr.sh em $(date '+%Y-%m-%d %H:%M:%S')"
  echo "# Uma linha por serviço: <NOME>_IMAGE=<referência completa com tag>"
  for i in "${!A_SVC[@]}"; do
    echo "$(svc_env_prefix "${A_SVC[$i]}")_IMAGE=${A_REF[$i]}"
  done
} > docs/images.env

# ---- docs/IMAGES.md (didático) ----
{
  echo "# Imagens das aplicações no ECR"
  echo ""
  echo "> Gerado automaticamente por \`05-build-push-ecr.sh\` em $(date '+%Y-%m-%d %H:%M:%S')."
  echo "> Registry: \`${REGISTRY}\` · Região: \`${REGION}\` · Tag: ${TAG_LABEL}"
  echo ""
  echo "## Referências das imagens"
  echo ""
  echo "| Serviço | Repositório ECR | Tag | Referência (campo \`image:\`) | Digest (pin imutável) |"
  echo "|---|---|---|---|---|"
  for i in "${!A_SVC[@]}"; do
    echo "| ${A_SVC[$i]} | ${A_REPO[$i]} | ${A_TAG[$i]} | \`${A_REF[$i]}\` | \`${A_REPO[$i]}@${A_DIGEST[$i]}\` |"
  done
  echo ""
  echo "## Blocos prontos para o Deployment"
  echo ""
  echo "Recomendado: fixar (pin) pela **tag específica** ou pelo **digest**"
  echo "(\`@sha256:...\`). Evite \`:latest\` em produção — dificulta rollback."
  echo ""
  for i in "${!A_SVC[@]}"; do
    echo "### ${A_SVC[$i]}"
    echo ""
    echo '```yaml'
    echo "    containers:"
    echo "      - name: ${A_SVC[$i]}"
    echo "        image: ${A_REF[$i]}          # pin por tag"
    echo "        # image: ${REGISTRY}/${A_REPO[$i]}@${A_DIGEST[$i]}   # (alternativa) pin por digest"
    echo "        imagePullPolicy: IfNotPresent   # tag fixa; use Always se for usar :latest"
    echo '```'
    echo ""
  done
  echo "## Para quem usa Kustomize"
  echo ""
  echo "Cole em \`kustomization.yaml\` para injetar as imagens sem editar cada Deployment:"
  echo ""
  echo '```yaml'
  echo "images:"
  for i in "${!A_SVC[@]}"; do
    echo "  - name: ${A_REPO[$i]}"
    echo "    newName: ${REGISTRY}/${A_REPO[$i]}"
    echo "    newTag: \"${A_TAG[$i]}\""
  done
  echo '```'
  echo ""
  echo "## Lembretes de deploy"
  echo ""
  echo "- **IRSA (permissão AWS sem chave):** o Deployment do **analytics** deve usar"
  echo "  \`serviceAccountName: analytics-sa\` (namespace \`analytics-service\`) e o do"
  echo "  **evaluation** deve usar \`serviceAccountName: evaluation-sa\` (namespace"
  echo "  \`evaluation-service\`) para herdar as permissões de SQS/DynamoDB."
  echo "- **Pull do ECR:** os nós do cluster já têm permissão de leitura do ECR —"
  echo "  **não** é preciso \`imagePullSecret\`."
  echo "- **Variáveis de ambiente** (endpoints de RDS/Redis, URL do SQS, tabela do"
  echo "  DynamoDB): veja a saída do \`04-outputs.sh\` e a tabela de handoff no \`README.md\`."
} > docs/IMAGES.md

# ------------------------------ 6. Resumo ----------------------------------
echo ""
echo "======================================================================"
echo " Concluído. ${#A_SVC[@]} imagens publicadas (tags em docs/IMAGES.md)."
echo " Artefatos atualizados:"
echo "   - docs/IMAGES.md   (tabela + blocos para os manifestos)"
echo "   - docs/images.env  (VAR=referência, para automação)"
echo "======================================================================"
