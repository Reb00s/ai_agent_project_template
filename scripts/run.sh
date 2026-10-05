#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; [ -f .env ] && . ./.env; set +a

if [ -z "${1:-}" ]; then
  echo "Использование: bash scripts/run.sh '<задача для агента>'"
  exit 1
fi

# --- Клиент Kimi Code CLI: проверка и автоустановка (официальный скрипт) ---
export PATH="$HOME/.local/bin:$PATH"
if ! command -v kimi >/dev/null 2>&1; then
  echo "Kimi Code CLI не найден — устанавливаю официальным скриптом..."
  curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash
fi
command -v kimi >/dev/null 2>&1 || { echo "FAIL: не удалось установить Kimi Code CLI"; exit 1; }

# --- Сбор стартового контекста (аналог автоподхвата AGENTS.md) ---
CONTEXT=$(cat AGENTS.md)
CONTEXT+=$'\n\n=== TASKS/CURRENT.MD ===\n'
CONTEXT+=$(cat tasks/current.md 2>/dev/null || echo "нет активной задачи")
CONTEXT+=$'\n\n=== ПОСЛЕДНЯЯ ЗАМЕТКА КОНТЕКСТА (конец context_log.md) ===\n'
CONTEXT+=$(tail -n 30 memory/context_log.md 2>/dev/null || echo "лог пуст")
CONTEXT+=$'\n\n=== MCP-ИСТОЧНИКИ ===\n'
CONTEXT+=$(cat mcp/mcp_config.json 2>/dev/null || echo "нет конфига MCP")
CONTEXT+=$'\n\n=== СКИЛЛЫ (skills/skills.md) ===\n'
CONTEXT+=$(cat skills/skills.md 2>/dev/null || echo "нет реестра скиллов")

RUN_DIR="workspace/runs/$(date +%Y-%m-%d)_$(echo "$1" | tr ' ' '_' | cut -c1-30)"
mkdir -p "$RUN_DIR/input" "$RUN_DIR/output" "$RUN_DIR/logs"

echo "$1" > "$RUN_DIR/input/prompt.txt"
echo "$CONTEXT" > "$RUN_DIR/input/context.md"

echo "Запуск: $RUN_DIR"
echo "Контекст собран: AGENTS.md + current.md + context_log + mcp_config + skills.md"
# TODO: подставь команду запуска твоего агента, например:
#   claude -p "$(cat "$RUN_DIR/input/context.md")" --append-system-prompt "$1"
#   или: agent run --context-file "$RUN_DIR/input/context.md" --task "$1"
