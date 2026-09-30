#!/bin/sh
# Перенос настроек после установки wdistr: разложить настройки программ из
# rsync-бэкапа хоста. Инструкция — handbook «Перенос настроек программ».
#
# Сейчас переносится только профиль Firefox, целиком, без выборки файлов:
# в нём физически лежит всё нужное — закладки и история (places.sqlite),
# настройки about:config (prefs.js — не отдельное хранилище, а файл профиля),
# расширения (extensions/*.xpi + extensions.json), их данные
# (browser-extension-data/), пароли (logins.json + key4.db), куки.
#
# Ловушка, которую обходит скрипт: нельзя просто скопировать ~/.mozilla/firefox.
# Firefox выбирает профиль так: сначала installs.ini — запись привязана к хэшу
# конкретной установки Firefox, на новой машине хэш другой и записи нет;
# дальше — профиль с Default=1 в profiles.ini. В бэкапе Default=1 стоит у
# ПУСТОГО профиля, а рабочий выбран через installs.ini. При слепом копировании
# новая система открыла бы пустой профиль. Поэтому: копируется только рабочий
# профиль (путь берётся из installs.ini) и генерируется чистый profiles.ini
# с Default=1 на него.
#
# Использование: setup.sh [путь-к-корню-бэкапа]
#   путь по умолчанию — внешний диск: /media/serg/4TB/rsync/home/serg
#   (аргумент нужен, например, для теста в VM, где диска нет — путь указывают
#   на залитую копию)

set -u

# Корень бэкапа: внутри него повторяется дерево /home (rsync/home/<пользователь>/...)
SRC="${1:-/media/serg/4TB/rsync/home/serg}"
SRC_FF="$SRC/.mozilla/firefox"
DST_FF="$HOME/.mozilla/firefox"

# Лог рядом с логом автоинициализации — читаемо пользователем и opencode
LOG="$HOME/install-log/settings.log"
mkdir -p "$HOME/install-log"

log() {
    echo "$1"
    echo "$(date -Is) $1" >> "$LOG"
}

# --- проверки до всяких изменений ---

log "== перенос настроек: начало =="

if [ ! -f "$SRC_FF/profiles.ini" ]; then
    log "ОШИБКА: нет $SRC_FF/profiles.ini — диск подключён? путь к бэкапу верный?"
    exit 1
fi

if [ -d "$DST_FF" ]; then
    log "ОШИБКА: $DST_FF уже существует — Firefox в этой системе уже запускался."
    log "Каталог не трогаю; если согласен перезаписать — удали его вручную и повтори."
    exit 1
fi

# --- определение рабочего профиля в бэкапе ---

# Рабочий профиль — тот, что закреплён за установкой Firefox: путь из строки
# Default= в installs.ini (это единственный Default-путь в файле)
PROFILE="$(awk -F= '/^Default=/ { print $2; exit }' "$SRC_FF/installs.ini" 2>/dev/null)"

# Фолбэк для бэкапа без installs.ini: секция профиля с Default=1.
# В секции профиля Path= идёт перед Default=1 (Install-секции без Path пропускаются)
if [ -z "$PROFILE" ] && [ -f "$SRC_FF/profiles.ini" ]; then
    PROFILE="$(awk '/^\[/ { p = "" } /^Path=/ { p = substr($0, 6) } /^Default=1$/ && p != "" { print p; exit }' "$SRC_FF/profiles.ini")"
fi

if [ -z "$PROFILE" ] || [ ! -d "$SRC_FF/$PROFILE" ]; then
    log "ОШИБКА: рабочий профиль в бэкапе не найден (installs.ini/profiles.ini)"
    exit 1
fi

# --- копирование и назначение по умолчанию ---

log "источник: $SRC"
log "рабочий профиль: $PROFILE"

mkdir -p "$DST_FF"
if ! cp -a "$SRC_FF/$PROFILE" "$DST_FF/"; then
    log "ОШИБКА: копирование профиля не удалось"
    exit 1
fi

# lock-файлы от чужой машины: без их удаления Firefox может считать профиль занятым
rm -f "$DST_FF/$PROFILE/lock" \
      "$DST_FF/$PROFILE/parent.lock" \
      "$DST_FF/$PROFILE/.parentlock"

# Чистый profiles.ini: единственный профиль с Default=1 — выбор однозначен,
# чужие записи installs.ini (хэш старой установки) не участвуют
cat > "$DST_FF/profiles.ini" <<EOF
[Profile0]
Name=default
IsRelative=1
Path=$PROFILE
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF

SIZE="$(du -sh "$DST_FF" | awk '{ print $1 }')"
log "готово: $DST_FF ($SIZE), профиль назначен по умолчанию"
log "== перенос настроек: завершён =="
