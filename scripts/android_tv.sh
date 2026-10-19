#!/usr/bin/env bash
# Управление Android TV приставкой (TOX3, 192.168.1.104) через SSH.
# Креды: TV_SSH_USER / TV_SSH_PASSWORD / TV_SSH_HOST в .env (в .gitignore).
# Сервер запрещает exec -> команды идут через интерактивный shell (ssh -tt),
# root — через su (Magisk уже выдал права SSH-приложению).
#
# Использование:
#   bash scripts/android_tv.sh health           — uptime/RAM/load/температура
#   bash scripts/android_tv.sh cmd <команда>    — выполнить от пользователя app
#   bash scripts/android_tv.sh root <команда>   — выполнить от root (su -c)
#   bash scripts/android_tv.sh shell            — интерактивный shell
#   bash scripts/android_tv.sh revive           — поднять SSH-сервер через ADB (если упал)
# Правило для этой приставки: НЕ использовать am force-stop через SSH-канал —
# убивает SSH-сервер (проверено эмпирически), очищать кэши без force-stop.
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_GET() { grep "^$1=" .env | cut -d= -f2-; }
USER_TV="$(ENV_GET TV_SSH_USER)"; PASS_TV="$(ENV_GET TV_SSH_PASSWORD)"; HOST_TV="$(ENV_GET TV_SSH_HOST)"
MODE="${1:?режим: health|cmd|root|shell}"; shift || true

ASKPASS="workspace/scratch/.askpass_tv"
printf '#!/bin/sh\necho "%s"\n' "$PASS_TV" > "$ASKPASS"; chmod 700 "$ASKPASS"
trap 'rm -f "$ASKPASS"' EXIT

SSH_BASE=(ssh -tt -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new
  -o PreferredAuthentications=password -o PubkeyAuthentication=no
  -o LogLevel=ERROR "$USER_TV@$HOST_TV")
export SSH_ASKPASS="$PWD/$ASKPASS" SSH_ASKPASS_REQUIRE=force

run_remote() { # $1 — shell-команда на приставке
  local b64; b64=$(printf '%s' "$1" | base64 -w0)
  # скрипт пишем в /sdcard (app-writable), выполняет его root, читаем без root
  (printf 'echo %s | base64 -d > /sdcard/.tv_cmd.sh; su -c "sh /sdcard/.tv_cmd.sh > /sdcard/.tv_cmd.out 2>&1"; cat /sdcard/.tv_cmd.out; rm /sdcard/.tv_cmd.sh /sdcard/.tv_cmd.out; exit\n' "$b64"; sleep "${TV_WAIT:-10}") \
    | timeout 40 "${SSH_BASE[@]}" 2>&1 | tr -d '\r' | sed 's/\x08\|\x1b\[[0-9;]*[A-Za-z]//g'
}

case "$MODE" in
  health) run_remote 'echo "==UPTIME=="; uptime; echo "==MEM=="; free -h | head -2; echo "==LOAD=="; cat /proc/loadavg; echo "==TEMP=="; for f in /sys/class/thermal/thermal_zone*/temp; do echo "$f: $(cat $f 2>/dev/null)"; done | head -4' ;;
  cmd)    run_remote "${1:?команда}" ;;
  root)   run_remote "su -c '$(printf '%s' "${1:?команда}" | sed "s/'/'\\\\''/g")'" ;;
  shell)  exec "${SSH_BASE[@]}" ;;
  revive)
    ADB="$HOME/.local/opt/platform-tools/adb"
    [ -x "$ADB" ] || { echo "adb не найден: $ADB" >&2; exit 1; }
    "$ADB" connect "$HOST_TV:5555" >/dev/null
    "$ADB" -s "$HOST_TV:5555" shell "monkey -p net.xnano.android.sshserver.tv -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1
    for i in 1 2 3; do
      sleep 6
      timeout 5 bash -c "echo > /dev/tcp/$HOST_TV/22" 2>/dev/null && { echo "SSH поднят"; exit 0; }
    done
    echo "SSH не поднялся — откройте приложение SSH Server на приставке" >&2; exit 1 ;;
  *) echo "Неизвестный режим: $MODE" >&2; exit 1 ;;
esac
