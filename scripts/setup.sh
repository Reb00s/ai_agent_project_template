#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# 1. Структура папок
for d in config mcp workspace/runs workspace/scratch tasks/archive memory skills; do
  mkdir -p "$d"
done
echo "OK: структура папок"

# 1b. Симлинки skills/ → .kimi-code/skills/ (авто-подхват скиллов в Kimi Code)
mkdir -p .kimi-code/skills
# чистим битые симлинки (скилл удалён из skills/)
for s in .kimi-code/skills/*; do
  [ -e "$s" ] || { rm -f "$s"; echo "Удалён битый симлинк: $s"; }
done
for d in skills/*/; do
  name=$(basename "$d")
  if [ -f "$d/SKILL.md" ]; then
    ln -sfn "../../skills/$name" ".kimi-code/skills/$name"
  fi
done
echo "OK: симлинки .kimi-code/skills/ ($(ls .kimi-code/skills | wc -l) шт.)"

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
