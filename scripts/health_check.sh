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

# 3b. Симлинки для авто-подхвата Kimi Code (создаёт setup.sh)
if [ -d .kimi-code/skills ]; then
  bad=0
  for s in .kimi-code/skills/*; do
    [ -e "$s" ] || { echo "FAIL: битый симлинк $s (перезапусти bash scripts/setup.sh)"; FAIL=1; bad=1; }
  done
  [ "$bad" -eq 0 ] && echo "OK: .kimi-code/skills/ (симлинки валидны)"
else
  echo "INFO: .kimi-code/skills/ нет — авто-подхват Kimi Code не настроен (создаст setup.sh)"
fi

# 3c. Секреты не в индексе git
if git rev-parse --git-dir >/dev/null 2>&1; then
  if git ls-files | grep -q '^\.kimi-code/mcp\.json$'; then
    echo "FAIL: .kimi-code/mcp.json в индексе git (может содержать креды)"; FAIL=1
  elif git grep -lI -e 'client-key-data' -e 'client-certificate-data' -- . ':(exclude)scripts/health_check.sh' >/dev/null 2>&1; then
    echo "FAIL: в индексе git есть файлы с данными kubeconfig"; FAIL=1
  else
    echo "OK: секреты не в индексе git"
  fi
fi
# kubeconfig локально (не обязателен для шаблона)
[ -f "$HOME/.kube/config" ] && echo "OK: ~/.kube/config есть" || echo "INFO: ~/.kube/config нет (запусти bash scripts/k8s_bootstrap.sh для подключения k8s)"

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
