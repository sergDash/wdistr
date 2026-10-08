#!/bin/sh
# Переключение раскладки us/ru по тапу Shift (keyd запускает скрипт фоном).
# Перенесено из /home/serg/bin/toggle-layout.sh (2026-09-27) с адаптацией путей.
#
# Сначала setxkbmap — X основное окружение, смена не должна ждать консоль;
# консоль secondary: loadkeys из ПРЕДСОБРАННЫХ карт (ckbcomp ~21 мс) против
# полной пересборки при вызове loadkeys по имени (~150 мс). Если файла нет —
# fallback на прямую сборку.

export DISPLAY=:0
# Файл авторизации — первого обычного пользователя (uid 1000+):
# имя из setup не захардкожено, скрипт работает при любом имени
XUSER=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}')
export XAUTHORITY="/home/$XUSER/.Xauthority"

STATE=/tmp/keyd-layout-state
MAPS=/usr/local/share/keyd

if [ ! -f "$STATE" ]; then
    echo us > "$STATE"
fi

case "$(cat "$STATE")" in
    us)
        # обязательно обе, иначе не работает ctrl+v
        setxkbmap -layout ru,us
        if [ -f "$MAPS/ru.txt" ]; then
            loadkeys "$MAPS/ru.txt" 2>>/tmp/keyd-lk.log
        else
            loadkeys ru 2>>/tmp/keyd-lk.log
            echo "fallback arg=ru" >>/tmp/keyd-lk.log
        fi
        echo ru > "$STATE"
        ;;
    ru)
        # обязательно обе, иначе не работает ctrl+v
        setxkbmap -layout us,ru
        if [ -f "$MAPS/us.txt" ]; then
            loadkeys "$MAPS/us.txt" 2>>/tmp/keyd-lk.log
        else
            loadkeys us 2>>/tmp/keyd-lk.log
            echo "fallback arg=us" >>/tmp/keyd-lk.log
        fi
        echo us > "$STATE"
        ;;
esac
