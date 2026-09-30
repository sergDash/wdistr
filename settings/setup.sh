#!/bin/sh
# Перенос настроек после установки wdistr: разложить настройки программ из
# rsync-бэкапа хоста. Инструкция — handbook «Перенос настроек программ».
#
# Переносятся профили Mozilla-программ (firefox, thunderbird), целиком, без
# выборки файлов — в профиле физически лежит всё пользовательское:
# firefox — закладки/история (places.sqlite), настройки about:config
#   (prefs.js — не отдельное хранилище, а файл профиля), расширения
#   (extensions/*.xpi + extensions.json), их данные (browser-extension-data/),
#   пароли (logins.json + key4.db), куки;
# thunderbird — письма (ImapMail), адресная книга (abook.sqlite), календарь,
#   расширения, пароли, PGP-ключи.
#
# Ловушка, которую обходит скрипт: нельзя просто скопировать каталог профиля.
# Firefox выбирает профиль так: сначала installs.ini — запись привязана к хэшу
# конкретной установки программы, на новой машине хэш другой и записи нет;
# дальше — профиль с Default=1 в profiles.ini. В бэкапе ОБОИХ программ
# Default=1 стоит у ПУСТОГО профиля, а рабочий выбран через installs.ini.
# При слепом копировании новая система открыла бы пустой профиль.
# Поэтому: копируется только рабочий профиль (путь берётся из installs.ini)
# и генерируется чистый profiles.ini с Default=1 на него.
#
# Использование: setup.sh [путь-к-корню-бэкапа]
#   путь по умолчанию — внешний диск: /media/serg/4TB/rsync/home/serg
#   (аргумент нужен, например, для теста в VM, где диска нет — путь указывают
#   на залитую копию)

set -u

# Корень бэкапа: внутри него повторяется дерево /home (rsync/home/<пользователь>/...)
SRC="${1:-/media/serg/4TB/rsync/home/serg}"

# Лог рядом с логом автоинициализации — читаемо пользователем и opencode
LOG="$HOME/install-log/settings.log"
mkdir -p "$HOME/install-log"

log() {
    echo "$1"
    echo "$(date -Is) $1" >> "$LOG"
}

# Перенос профиля одной программы: <имя> <каталог-источника> <каталог-назначения>
# Возвращает 0 (перенесено или пропущено) и 1 (ошибка — не трогать назначение).
install_profile() {
    NAME="$1"
    SRC_FF="$2"
    DST_FF="$3"

    # Программы может не быть в бэкапе — это не ошибка, просто пропуск
    if [ ! -f "$SRC_FF/profiles.ini" ]; then
        log "$NAME: пропущено — в бэкапе нет $SRC_FF/profiles.ini"
        return 0
    fi

    # Назначение занято (программу уже запускали) — не перезаписываем
    if [ -d "$DST_FF" ]; then
        log "$NAME: ОШИБКА — $DST_FF уже существует, каталог не трогаю."
        log "$NAME: Если согласен перезаписать — удали его вручную и повтори."
        return 1
    fi

    # Рабочий профиль — тот, что закреплён за установкой программы: путь из
    # строки Default= в installs.ini (это единственный Default-путь в файле)
    PROFILE="$(awk -F= '/^Default=/ { print $2; exit }' "$SRC_FF/installs.ini" 2>/dev/null)"

    # Фолбэк для бэкапа без installs.ini: секция профиля с Default=1.
    # В секции профиля Path= идёт перед Default=1 (Install-секции без Path пропускаются)
    if [ -z "$PROFILE" ] && [ -f "$SRC_FF/profiles.ini" ]; then
        PROFILE="$(awk '/^\[/ { p = "" } /^Path=/ { p = substr($0, 6) } /^Default=1$/ && p != "" { print p; exit }' "$SRC_FF/profiles.ini")"
    fi

    if [ -z "$PROFILE" ] || [ ! -d "$SRC_FF/$PROFILE" ]; then
        log "$NAME: ОШИБКА — рабочий профиль в бэкапе не найден (installs.ini/profiles.ini)"
        return 1
    fi

    log "$NAME: источник $SRC_FF, рабочий профиль $PROFILE"

    mkdir -p "$DST_FF"
    if ! cp -a "$SRC_FF/$PROFILE" "$DST_FF/"; then
        log "$NAME: ОШИБКА — копирование профиля не удалось"
        return 1
    fi

    # lock-файлы от чужой машины: без их удаления программа может считать профиль занятым
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
    log "$NAME: готово — $DST_FF ($SIZE), профиль назначен по умолчанию"
    return 0
}

# --- проверки до всяких изменений ---

log "== перенос настроек: начало =="

# Диск подключён, если в корне бэкапа нашёлся хотя бы один каталог профиля
if [ ! -f "$SRC/.mozilla/firefox/profiles.ini" ] && [ ! -f "$SRC/.thunderbird/profiles.ini" ]; then
    log "ОШИБКА: в $SRC нет ни firefox, ни thunderbird — диск подключён? путь к бэкапу верный?"
    exit 1
fi

log "источник: $SRC"

# --- разложение по программам ---

FAIL=0
install_profile firefox   "$SRC/.mozilla/firefox" "$HOME/.mozilla/firefox"     || FAIL=1
install_profile thunderbird "$SRC/.thunderbird"   "$HOME/.thunderbird"         || FAIL=1

if [ "$FAIL" -ne 0 ]; then
    log "== перенос настроек: завершён с ошибками =="
    exit 1
fi

log "== перенос настроек: завершён =="
