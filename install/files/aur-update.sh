#!/bin/sh
# Автообновление AUR-пакетов (wdistr). Обновляется ТОЛЬКО AUR (yay -Sua):
# сама система обновляется вручную — отношение «на самотек» (AGENTS.md).
# Запускается таймером wdistr-aur-update.timer, лог — install-log/aur-update.log.
set -u

USER_NAME="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }')"
USER_HOME="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $6; exit }')"
LOGDIR="$USER_HOME/install-log"
LOG="$LOGDIR/aur-update.log"

mkdir -p "$LOGDIR"
echo "== AUR-обновление: $(date -Is) ==" >>"$LOG"

sudo -u "$USER_NAME" env HOME="$USER_HOME" \
    yay -Sua --noconfirm >>"$LOG" 2>&1
echo "  rc=$?" >>"$LOG"

chown -R "$(stat -c %U:%G "$USER_HOME")" "$LOGDIR"
