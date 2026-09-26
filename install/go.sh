#!/bin/sh
# Установка нашей системы одной командой из живой среды Arch.
# Вход: этот скрипт отдаёт HTTP-сервер хоста (10.0.2.2:8000), конфиги — те же.
# Выход: запуск archinstall в тихом режиме; аргументы пробрасываются дальше
#        (например, --dry-run для проверки без установки).

BASE="http://10.0.2.2:8000/install"

exec archinstall \
    --config-url "$BASE/archinstall-config.json" \
    --creds-url "$BASE/archinstall-creds.json" \
    --silent "$@"
