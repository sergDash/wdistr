#!/bin/sh
# Установка нашей системы одной командой.
# Логика: если конфиги лежат локально — берём их (наш ISO, /root/wdistr);
# иначе — стоковая живая среда при разработке, качаем с dev-сервера хоста
# (10.0.2.2:8000, запущенного на хосте из корня репозитория).
# Аргументы пробрасываются в archinstall (например, --dry-run).
# --offline — зеркала только из локального mirrorlist, не с archlinux.org
# (см. комментарий в /usr/local/bin/setup).
# ВАЖНО: копия этого файла вшивается в ISO — iso/airootfs/root/wdistr/go.sh,
# обновлять оба одновременно.

LOCAL="/root/wdistr"

if [ -f "$LOCAL/archinstall-config.json" ]; then
    exec archinstall \
        --config "$LOCAL/archinstall-config.json" \
        --creds "$LOCAL/archinstall-creds.json" \
        --silent --offline "$@"
fi

BASE="http://10.0.2.2:8000/install"

exec archinstall \
    --config-url "$BASE/archinstall-config.json" \
    --creds-url "$BASE/archinstall-creds.json" \
    --silent --offline "$@"
