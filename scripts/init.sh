#!/usr/bin/env bash
# Инициализация проекта на новой машине. Запускать первым: поднимает всё
# необходимое и передаёт работу агенту. Идемпотентен — повторный запуск
# пропускает готовое. Секреты не хранит: SSH-креды для k8s спрашиваются
# интерактивно в k8s_bootstrap.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== 1/4 Клиент Kimi Code CLI =="
export PATH="$HOME/.local/bin:$PATH"
if command -v kimi >/dev/null 2>&1; then
  echo "уже установлен: $(command -v kimi)"
else
  echo "не найден — устанавливаю официальным скриптом..."
  curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash
fi
command -v kimi >/dev/null 2>&1 || { echo "FAIL: не удалось установить Kimi Code CLI"; exit 1; }

echo "== 2/4 Структура проекта, симлинки скиллов, .env =="
bash scripts/setup.sh

echo "== 3/4 Подключение к Kubernetes через MCP (опционально) =="
if [ -f "$HOME/.kube/config" ]; then
  echo "kubeconfig уже есть (~/.kube/config) — пропускаю"
else
  read -r -p "Подключить кластер k8s (спросит SSH-креды)? [y/N]: " ans
  case "${ans:-}" in
    y|Y) bash scripts/k8s_bootstrap.sh ;;
    *)   echo "пропущено — позже: bash scripts/k8s_bootstrap.sh" ;;
  esac
fi

echo "== 4/4 Проверка окружения =="
bash scripts/health_check.sh || true   # FAIL'ы — подсказки, не стоп

cat <<'EOF'
=== Готово. Как продолжить ===
  Интерактивно:  kimi
  Одной задачей: bash scripts/run.sh '<задача для агента>'
EOF
read -r -p "Запустить kimi сейчас? [y/N]: " run
case "${run:-}" in
  y|Y) exec kimi ;;
  *)   echo "Ок — запускайте, когда будете готовы." ;;
esac
