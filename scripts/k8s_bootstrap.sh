#!/usr/bin/env bash
# Bootstrap подключения к k8s-серверу: создаёт ServiceAccount с правами,
# забирает токен и собирает локальный kubeconfig + .kimi-code/mcp.json.
# Секреты НЕ логируются и НЕ попадают в репозиторий.
# Идемпотентен: повторный запуск перевыпускает токен.
# Требует: ssh-доступа (пароль спросит ssh), kubectl на сервере.
# Переопределяемо: K8S_SERVER, K8S_API, K8S_SA_NAMESPACE, K8S_SA_NAME, KUBECONFIG_OUT
set -euo pipefail
cd "$(dirname "$0")/.."

SERVER="${K8S_SERVER:-reb00s@192.168.1.111}"
API="${K8S_API:-https://192.168.1.111:6443}"
SA_NS="${K8S_SA_NAMESPACE:-default}"
SA_NAME="${K8S_SA_NAME:-kimi-agent}"
OUT="${KUBECONFIG_OUT:-$HOME/.kube/config}"
MCP_JSON=".kimi-code/mcp.json"

echo "== 1/3 Создание ServiceAccount и токена на сервере =="
REMOTE_OUT=$(ssh -o ConnectTimeout=10 -o NumberOfPasswordPrompts=3 "$SERVER" \
  bash -s -- "$SA_NS" "$SA_NAME" <<'REMOTE'
set -euo pipefail
NS="$1"; SA="$2"
kubectl get ns "$NS" >/dev/null
kubectl create sa "$SA" -n "$NS" 2>/dev/null || echo "SA $SA уже есть" >&2
kubectl create clusterrolebinding "${SA}-cluster-admin" \
  --clusterrole=cluster-admin --serviceaccount="$NS:$SA" 2>/dev/null \
  || echo "binding уже есть" >&2
TOKEN=$(kubectl create token "$SA" -n "$NS" --duration=8760h)
CA=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="default")].cluster.certificate-authority-data}')
[ -n "$CA" ] || CA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
printf 'TOKEN=%s\nCA=%s\n' "$TOKEN" "$CA"
REMOTE
)

TOKEN=$(printf '%s\n' "$REMOTE_OUT" | sed -n 's/^TOKEN=//p')
CA=$(printf '%s\n' "$REMOTE_OUT" | sed -n 's/^CA=//p')
[ -n "$TOKEN" ] && [ -n "$CA" ] || { echo "FAIL: не получен токен/CA"; exit 1; }

echo "== 2/3 Запись kubeconfig в $OUT (права 600) =="
[ -f "$OUT" ] && cp "$OUT" "$OUT.bak.$(date +%Y%m%d%H%M%S)" && echo "существующий конфиг сохранён как бэкап"
mkdir -p "$(dirname "$OUT")"; chmod 700 "$(dirname "$OUT")"
umask 077
cat > "$OUT" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CA}
    server: ${API}
  name: k3s-iamodels
contexts:
- context:
    cluster: k3s-iamodels
    user: ${SA_NAME}
  name: ${SA_NAME}@k3s-iamodels
current-context: ${SA_NAME}@k3s-iamodels
users:
- name: ${SA_NAME}
  user:
    token: ${TOKEN}
EOF
chmod 600 "$OUT"
echo "kubeconfig записан"

echo "== 3/3 Генерация $MCP_JSON (без секретов) =="
mkdir -p .kimi-code
cat > "$MCP_JSON" <<EOF
{
  "mcpServers": {
    "kubernetes": {
      "command": "npx",
      "args": ["-y", "mcp-server-kubernetes"],
      "env": {
        "PATH": "$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin",
        "KUBECONFIG": "$OUT"
      }
    }
  }
}
EOF
echo "$MCP_JSON записан (в .gitignore)"

echo "Готово. Проверка: kubectl --kubeconfig $OUT get nodes"
kubectl --kubeconfig "$OUT" get nodes
