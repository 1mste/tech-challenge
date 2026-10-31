#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Cria as tabelas nos 3 bancos PostgreSQL.
#
# Por que e necessario: nenhuma das aplicacoes cria as proprias tabelas na
# inicializacao. Os arquivos postgres/*/*.sql so sao aplicados sozinhos pelo
# docker-compose, no ambiente local. Na AWS, alguem precisa roda-los.
#
# Sintoma de esquecer: os pods ficam Running e Healthy (o /health nao toca
# o banco), mas qualquer chamada de verdade responde 500.
#
# Como funciona: o RDS vive em subnet privada, inalcancavel da sua maquina.
# Entao o script sobe um pod temporario com o cliente psql DENTRO do cluster
# e aplica o SQL de la. A senha nao passa pela linha de comando — vem da
# Secret que ja existe no namespace.
#
#   ./scripts/apply-schema.sh
#
# Idempotente: os SQLs usam CREATE TABLE IF NOT EXISTS e CREATE OR REPLACE.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."
command -v jq >/dev/null || { echo "ERRO: instale o jq."; exit 1; }

PG_IMAGE="${PG_IMAGE:-postgres:16-alpine}"

# servico : arquivo SQL
MAPA="auth:postgres/auth/auth-init.sql
flag:postgres/flag/flags-init.sql
targeting:postgres/targeting/targeting-init.sql"

FALHAS=0

while IFS=: read -r svc sql; do
  ns="${svc}-service"
  echo "══ ${ns}"

  if [ ! -f "$sql" ]; then
    echo "   ✗ arquivo nao encontrado: $sql"; FALHAS=$((FALHAS+1)); continue
  fi
  if ! kubectl -n "$ns" get secret "${svc}-secret" >/dev/null 2>&1; then
    echo "   ✗ Secret ${svc}-secret nao existe. Rode ./scripts/create-secrets.sh antes."
    FALHAS=$((FALHAS+1)); continue
  fi

  # O SQL vai em base64 por variavel de ambiente. Evita o stdin do kubectl
  # (que as vezes nao anexa) e qualquer problema de aspas — os triggers usam
  # dollar-quoting ($$), que quebraria se interpolado na linha de comando.
  SQL_B64=$(base64 -w0 < "$sql")
  POD="schema-${svc}-$$"

  OVERRIDES=$(jq -n --arg img "$PG_IMAGE" --arg b64 "$SQL_B64" --arg sec "${svc}-secret" '{
    spec: {
      restartPolicy: "Never",
      containers: [{
        name: "psql",
        image: $img,
        command: ["sh","-c","echo \"$SQLB64\" | base64 -d | psql \"$DATABASE_URL\" -v ON_ERROR_STOP=1"],
        env: [{ name: "SQLB64", value: $b64 }],
        envFrom: [{ secretRef: { name: $sec } }]
      }]
    }
  }')

  if kubectl -n "$ns" run "$POD" --rm --attach --restart=Never \
       --image="$PG_IMAGE" --overrides="$OVERRIDES" 2>&1 \
       | grep -vE "^pod .* deleted$" | sed 's/^/   /'; then
    echo "   ✓ schema aplicado"
  else
    echo "   ✗ falhou"; FALHAS=$((FALHAS+1))
  fi
done <<< "$MAPA"

echo
if [ "$FALHAS" -eq 0 ]; then
  echo "Os 3 schemas foram aplicados."
else
  echo "ATENCAO: $FALHAS banco(s) com falha." >&2
  exit 1
fi
