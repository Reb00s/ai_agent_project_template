#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# 1. Структура папок
for d in config mcp workspace/runs workspace/scratch tasks/archive memory skills; do
  mkdir -p "$d"
done
echo "OK: структура папок"

# 2. .env
if [ ! -f .env ]; then
  cp .env.example .env
  echo "Создан .env из шаблона — заполни его (LLM_API_KEY, LLM_MODEL, ...)"
else
  echo "OK: .env уже есть"
fi

# 3. Валидация синтаксиса конфигов (не фATAL — предупреждаем)
if command -v python3 >/dev/null; then
  if [ -f mcp/mcp_config.json ]; then
    python3 -m json.tool mcp/mcp_config.json >/dev/null 2>&1 \
      && echo "OK: mcp/mcp_config.json (json валиден)" \
      || echo "WARN: mcp/mcp_config.json не парсится как json"
  fi
  if [ -f config/settings.yaml ]; then
    python3 -c "import yaml; yaml.safe_load(open('config/settings.yaml'))" >/dev/null 2>&1 \
      && echo "OK: config/settings.yaml (yaml валиден)" \
      || echo "INFO: config/settings.yaml не провалидирован (нет модуля yaml — не критично)"
  fi
else
  echo "INFO: python3 не найден — конфиги не валидировались"
fi

echo "Далее:"
echo "  1. Заполни .env"
echo "  2. bash scripts/health_check.sh"
echo "  3. Диктуй агенту задачу (новая задача → grill-me, см. skills/skills.md)"
