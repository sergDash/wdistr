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

# Снапшот-эталон ПЕРЕД обновлением (решение 2026-10-13): откат к
# состоянию до pacman -Syu. flock сервиса (/run/wdistr.lock) сериализует
# снапшот с распаковкой — снимок не попадёт в середину транзакции.
# Если timeshift не настроен — обновление всё равно продолжается,
# его rc пишется в лог.
echo "+ timeshift --create (снапшот до обновления)" >>"$LOG"
timeshift --create --scripted --comments "до обновления $(date +%F)" >>"$LOG" 2>&1
echo "  rc=$?" >>"$LOG"

pacman -Syu --noconfirm >>"$LOG" 2>&1
echo "  rc=$?" >>"$LOG"
chown -R "$(stat -c %U:%G "$USER_HOME")" "$LOGDIR"
