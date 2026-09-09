#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Загрузка .env
set -a; [ -f .env ] && . ./.env; set +a

if [ -z "${1:-}" ]; then
  echo "Использование: bash scripts/run.sh '<задача для агента>'"
  exit 1
fi

RUN_DIR="workspace/runs/$(date +%Y-%m-%d)_task"
mkdir -p "$RUN_DIR/input" "$RUN_DIR/output" "$RUN_DIR/logs"

echo "$1" > "$RUN_DIR/input/prompt.txt"
echo "Запуск: $RUN_DIR"
echo "TODO: подставь команду запуска твоего агента/фреймворка здесь."
