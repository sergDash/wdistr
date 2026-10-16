#!/bin/sh
# Автообновление СИСТЕМЫ (wdistr): еженедельно, таймер wdistr-sys-update.
# pacman -Syu идёт от root (сервис), пароль не нужен; лог —
# install-log/sys-update.log, читаемо пользователем и агентом.
set -u

USER_HOME="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $6; exit }')"
LOGDIR="$USER_HOME/install-log"
LOG="$LOGDIR/sys-update.log"

mkdir -p "$LOGDIR"
echo "== обновление системы: $(date -Is) ==" >>"$LOG"
pacman -Syu --noconfirm >>"$LOG" 2>&1
RC=$?
echo "  rc=$RC" >>"$LOG"
chown -R "$(stat -c %U:%G "$USER_HOME")" "$LOGDIR"
# Код сбоя наружу — по нему сервис включает повтор через 4 часа
# (OnFailure, шаблон wdistr-update-retry@; без exit код гасил chown)
exit "$RC"
