#!/bin/sh
# Автоинициализация при первом запуске системы (wdistr).
# Состав согласован 2026-09-26: обновление пакетов и баз (включая multilib),
# подключение flathub. Лог пишется в ~/install-log/first-boot.log —
# читаемо пользователем и агентом opencode (сценарий самопроверки).
set -u

# Первый обычный пользователь системы (uid >= 1000) — владелец логов
USER_HOME="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $6; exit }')"
LOGDIR="$USER_HOME/install-log"
LOG="$LOGDIR/first-boot.log"

mkdir -p "$LOGDIR"

echo "== wdistr: инициализация первого запуска: $(date -Is) ==" >>"$LOG"

# run: команда + её код возврата — в лог, для разбора потом
run() {
    echo "+ $*" >>"$LOG"
    "$@" >>"$LOG" 2>&1
    echo "  rc=$?" >>"$LOG"
}

# 1. Базы всех репозиториев (multilib включён, но база не скачана) + актуальность
run pacman -Syu --noconfirm

# 2. Flathub для flatpak-программ (список программ — отдельной задачей)
run flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Логи принадлежат пользователю, чтобы читать без root
chown -R "$(stat -c %U:%G "$USER_HOME")" "$LOGDIR"

echo "== инициализация завершена: $(date -Is) ==" >>"$LOG"
