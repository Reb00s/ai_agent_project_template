#!/usr/bin/env bash
# Деплой Crawl4AI (парсер сайтов) в локальный k8s-кластер как MCP-сервер.
# Секреты берёт из .env (в .gitignore): CRAWL4AI_API_TOKEN, SECRET_KEY.
# При отсутствии — генерирует и дописывает в .env.
set -euo pipefail
cd "$(dirname "$0")/.."

export PATH="$HOME/.local/bin:$PATH"

ENV_FILE=".env"
touch "$ENV_FILE"

ensure_var() { # $1 — имя переменной
  if ! grep -q "^$1=" "$ENV_FILE"; then
    echo "$1=$(openssl rand -hex 32)" >> "$ENV_FILE"
    echo "  сгенерирован $1 -> $ENV_FILE"
  fi
}

echo "== Crawl4AI: проверка секретов в $ENV_FILE =="
ensure_var CRAWL4AI_API_TOKEN
ensure_var SECRET_KEY

TOKEN=$(grep "^CRAWL4AI_API_TOKEN=" "$ENV_FILE" | cut -d= -f2)
SECRET=$(grep "^SECRET_KEY=" "$ENV_FILE" | cut -d= -f2)

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl не найден. Сначала: bash scripts/k8s_bootstrap.sh" >&2
  exit 1
fi

echo "== Secret crawl4ai-auth (namespace harness) =="
kubectl create namespace harness --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: crawl4ai-auth
  namespace: harness
type: Opaque
stringData:
  CRAWL4AI_API_TOKEN: "$TOKEN"
  SECRET_KEY: "$SECRET"
EOF

echo "== Применение манифеста mcp/k8s/crawl4ai.yaml =="
kubectl apply -f mcp/k8s/crawl4ai.yaml

echo "== Ожидание готовности пода =="
kubectl -n harness rollout status deployment/crawl4ai --timeout=180s

echo "== Проверка =="
sleep 3
curl -s -m 15 -o /dev/null -w "/health -> HTTP %{http_code}\n" \
  http://192.168.1.111:30112/health || true

cat <<'TIP'
Готово. MCP-подключение для .kimi-code/mcp.json:
  "crawl4ai": {
    "transport": "sse",
    "url": "http://192.168.1.111:30112/mcp/sse",
    "headers": { "Authorization": "Bearer $CRAWL4AI_API_TOKEN" }
  }
Токен — из .env. Инструменты: md, html, screenshot, pdf, execute_js, crawl, ask.
TIP
