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
RC=$?
echo "  rc=$RC" >>"$LOG"

# Решение 2026-11-08: после успеха — полная очистка кэша сборок yay
# (~/.cache/yay), без хранения прошлых сборок. При падении обновления
# чистить нельзя: повтор добирает недостающие источники из кэша — та же
# логика, что в first-boot. --noconfirm: yay берёт ответ по умолчанию
# «да» без чтения stdin, в сервисе ввода нет.
if [ "$RC" -eq 0 ]; then
    echo "+ очистка кэша yay" >>"$LOG"
    sudo -u "$USER_NAME" env HOME="$USER_HOME" \
        yay -Scc --noconfirm >>"$LOG" 2>&1
    echo "  rc=$? (yay -Scc)" >>"$LOG"
fi

chown -R "$(stat -c %U:%G "$USER_HOME")" "$LOGDIR"
# Код сбоя наружу — по нему сервис включает повтор через 4 часа
exit "$RC"
