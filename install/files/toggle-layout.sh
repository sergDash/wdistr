#!/bin/sh
# Переключение раскладки us/ru по тапу Shift (keyd запускает скрипт фоном).
# Перенесено из /home/serg/bin/toggle-layout.sh с адаптацией под дистрибутив:
# - XAUTHORITY — пользователь дистрибутива (user);
# - предсобранные карты ckbcomp не используются: пакета в extra нет;
#   работает прямой loadkeys (~150 мс по замерам автора против 21 мс с картами;
#   если понадобит скорость — вернуть ckbcomp-карты в сборку).

export DISPLAY=:0
export XAUTHORITY=/home/user/.Xauthority

STATE=/tmp/keyd-layout-state

if [ ! -f "$STATE" ]; then
    echo us > "$STATE"
fi

# Порядок: сначала setxkbmap (X — основное окружение), консоль — следом.
# Всё, что набрано во время переключения, уходит в старую раскладку.
case "$(cat "$STATE")" in
    us)
        setxkbmap -layout ru,us
        loadkeys ru 2>>/tmp/keyd-lk.log || echo "loadkeys ru rc=$?" >>/tmp/keyd-lk.log
        echo ru > "$STATE"
        ;;
    ru)
        setxkbmap -layout us,ru
        loadkeys us 2>>/tmp/keyd-lk.log || echo "loadkeys us rc=$?" >>/tmp/keyd-lk.log
        echo us > "$STATE"
        ;;
esac
