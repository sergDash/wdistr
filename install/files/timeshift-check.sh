#!/bin/sh
# Проверка расписания Timeshift (wdistr): ежечасно, таймер
# wdistr-timeshift-check. timeshift --check сам решает по timeshift.json,
# пора ли снимать (daily/weekly), — создание снапшота и обновления
# разведены общим flock у сервиса. Лог — install-log/timeshift-check.log.
set -u

USER_HOME="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $6; exit }')"
LOGDIR="$USER_HOME/install-log"
LOG="$LOGDIR/timeshift-check.log"

mkdir -p "$LOGDIR"
echo "== проверка Timeshift: $(date -Is) ==" >>"$LOG"
timeshift --check --scripted >>"$LOG" 2>&1
echo "  rc=$?" >>"$LOG"
chown -R "$(stat -c %U:%G "$USER_HOME")" "$LOGDIR"
