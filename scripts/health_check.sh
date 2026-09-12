#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
FAIL=0

# 1. .env заполнен
if [ ! -f .env ]; then echo "FAIL: нет .env (запусти bash scripts/setup.sh)"; FAIL=1;
elif grep -q '=\s*$' .env; then echo "FAIL: в .env есть пустые значения"; FAIL=1;
else echo "OK: .env"; fi

# 2. Структура папок
for d in config mcp workspace tasks memory skills scripts; do
  [ -d "$d" ] && echo "OK: $d/" || { echo "FAIL: нет $d/"; FAIL=1; }
done
for d in workspace/runs workspace/scratch tasks/archive; do
  [ -d "$d" ] || { echo "FAIL: нет $d/ (запусти bash scripts/setup.sh)"; FAIL=1; }
done

# 3. Скиллы: реестр и сами папки
if [ -f skills/skills.md ]; then
  echo "OK: skills/skills.md"
  n=$(find skills -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l)
  if [ "$n" -eq 0 ]; then echo "FAIL: в skills/ нет ни одного скилла (ожидался skills/grill-me/)"; FAIL=1;
  else
    for s in skills/*/SKILL.md; do
      echo "OK: скилл $(basename "$(dirname "$s")")"
    done
  fi
else
  echo "FAIL: нет skills/skills.md"; FAIL=1
fi

# 4. Конфиги валидны
if command -v python3 >/dev/null; then
  if [ -f mcp/mcp_config.json ]; then
    python3 -m json.tool mcp/mcp_config.json >/dev/null 2>&1 \
      && echo "OK: mcp/mcp_config.json" \
      || { echo "FAIL: mcp/mcp_config.json не парсится"; FAIL=1; }
  fi
else
  echo "INFO: python3 нет — json-конфиг не провалидирован"
fi

# 5. MCP smoke-тесты и evals — TODO при подключении реальных серверов
#    (скелет: mcp/tests/, config/evals/)

[ "$FAIL" -eq 0 ] && echo "=== Все проверки пройдены ===" || { echo "=== Есть проблемы ==="; exit 1; }
