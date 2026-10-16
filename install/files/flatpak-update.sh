#!/bin/sh
# Автообновление FLATPAK (wdistr): еженедельно, таймер wdistr-flatpak-update.
# Обновляет все установленные приложения и рантаймы системного
# flatpak-репозитория; лог — install-log/flatpak-update.log.
set -u

USER_HOME="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $6; exit }')"
LOGDIR="$USER_HOME/install-log"
LOG="$LOGDIR/flatpak-update.log"

mkdir -p "$LOGDIR"
echo "== обновление flatpak: $(date -Is) ==" >>"$LOG"
flatpak update --noninteractive -y >>"$LOG" 2>&1
RC=$?
echo "  rc=$RC" >>"$LOG"
chown -R "$(stat -c %U:%G "$USER_HOME")" "$LOGDIR"
# Код сбоя наружу — по нему сервис включает повтор через 4 часа
exit "$RC"
