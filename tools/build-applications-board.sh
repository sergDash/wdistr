#!/bin/bash
# Сборка доски приложений: applications.png — 63 GUI-иконки дистрибутива
# на чёрном фоне, перемешанные (решение 2026-10-23).
#
# Состав и порядок иконок — Cards/Доска приложений - Планирование иконок.md.
# Имена файлов иконок проверены на рабочей машине 2026-10-23.
#
# Зависимости: imagemagick (montage), librsvg (rsvg-convert), papirus-icon-theme.
# Запуск: bash tools/build-applications-board.sh [путь/к/выходу.png]
# Выход по умолчанию: applications.png в корне репозитория.

set -euo pipefail

# Репозиторий — уровень выше tools/
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$REPO/applications.png}"
WORK="$(mktemp -d /tmp/wdistr-board.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/png"

# Таблица иконок: имя_программы|иконка|источник|подпись
# Подпись — человекочитаемое имя; для длинных двухсловных — две строки (\n).
# Порядок строк — порядок в карточке; на доске порядок перемешивается (shuf).
cat > "$WORK/icons.tsv" << 'EOF'
firefox|firefox|Papirus|Firefox
thunderbird|thunderbird|Papirus|Thunderbird
discord|discord|Papirus|Discord
element-desktop|element-desktop|Papirus|Element
signal-desktop|signal-desktop|Papirus|Signal
deltachat-desktop|deltachat-desktop|Papirus|Deltachat
session-desktop|session-desktop|Papirus|Session
whatsie|whatsie|Papirus|WhatSie
teamspeak3|teamspeak3|Papirus|TeamSpeak
mousepad|mousepad|Papirus|Mousepad
nemo|nemo|Papirus|Nemo
neovim|nvim|hicolor|NeoVim
vscodium|vscodium|Papirus|VSCodium
pragtical|pragtical|hicolor|Pragtical
obsidian|obsidian|Papirus|Obsidian
wordcraft|ai.storyteller.wordcraft|hicolor|WordCraft
gridcraft|ai.storyteller.gridcraft|hicolor|GridCraft
drawio|drawio|Papirus|draw.io
libreoffice-writer|libreoffice-writer|Papirus|Writer
libreoffice-calc|libreoffice-calc|Papirus|Calc
libreoffice-impress|libreoffice-impress|Papirus|Impress
libreoffice-draw|libreoffice-draw|Papirus|Draw
libreoffice-base|libreoffice-base|Papirus|Base
libreoffice-math|libreoffice-math|Papirus|Math
java|java27-openjdk|hicolor|Java
virtualbox|virtualbox|Papirus|VirtualBox
gimp|gimp|Papirus|GIMP
inkscape|inkscape|Papirus|Inkscape
blender|blender|Papirus|Blender
photocraft|ai.storyteller.photocraft|hicolor|PhotoCraft
vectorcraft|ai.storyteller.vectorcraft|hicolor|VectorCraft
audacity|audacity|Papirus|Audacity
audacious|audacious|Papirus|Audacious
mpv|mpv|Papirus|mpv
viewnior|viewnior|Papirus|Viewnior
file-roller|file-roller|Papirus|File\nRoller
okular|okular|Papirus|Okular
android-studio|android-studio|Papirus|Android\nStudio
arduino-ide|arduino-ide|Papirus|Arduino
librepcb|org.librepcb.LibrePCB|Papirus|LibrePCB
beekeeper-studio|beekeeper-studio|Papirus|Beekeeper\nStudio
godot|godot|Papirus|Godot
xmind|xmind|Papirus|XMind
meld|meld|Papirus|Meld
zeal|zeal|Papirus|Zeal
ghostty|com.mitchellh.ghostty|Papirus|Ghostty
keepassxc|keepassxc|Papirus|KeePassXC
authenticator|com.belmoussaoui.Authenticator|Papirus|Authenticator
copyq|copyq|Papirus|CopyQ
qbittorrent|qbittorrent|Papirus|qBittorrent
flameshot|flameshot|Papirus|Flameshot
flatseal|com.github.tchx84.Flatseal|Papirus|Flatseal
baobab|baobab|Papirus|Baobab
gnome-calculator|gnome-calculator|Papirus|Calculator
gnome-disk-utility|gnome-disks|Papirus|Disks
timeshift|timeshift|Papirus|Timeshift
system-config-printer|system-config-printer|Papirus|Printers
solaar|solaar|Papirus|Solaar
openrgb|openrgb|Papirus|OpenRGB
sticky|sticky|Papirus|Sticky
emote|emote|hicolor|Emote
stellarium|stellarium|Papirus|Stellarium
syncthing|syncthing|Papirus|Syncthing
localsend|localsend|Papirus|LocalSend
amneziavpn|AmneziaVPN|Papirus|Amnezia\nVPN
jan|Jan|hicolor|Jan
lmstudio|lmstudio-bin|hicolor|LM\nStudio
qpwgraph|org.rncbc.qpwgraph|hicolor|qpwgraph
dash-core|org.dash.dash-core|flatpak|Dash
steam|steam|Papirus|Steam
protonup-qt|protonup-qt|Papirus|ProtonUp-Qt
portproton|portproton|Papirus|PortProton
EOF

FOUND=0
MISSING=0

while IFS='|' read -r app icon src label; do
    out="$WORK/png/${app}.png"
    done_flag=0

    if [ "$src" = "Papirus" ]; then
        # SVG: 128×128, затем 96, 64 (у VirtualBox максимум 64), затем растр
        for cand in \
            "/usr/share/icons/Papirus/128x128/apps/${icon}.svg" \
            "/usr/share/icons/Papirus/96x96/apps/${icon}.svg" \
            "/usr/share/icons/Papirus/64x64/apps/${icon}.svg" \
            "/usr/share/icons/Papirus/128x128/apps/${icon}.png" \
            "/usr/share/icons/Papirus/96x96/apps/${icon}.png"; do
            if [ -f "$cand" ]; then
                if [[ "$cand" == *.svg ]]; then
                    rsvg-convert -w 128 -h 128 "$cand" -o "$out"
                else
                    magick "$cand" -resize 128x128 \
                        -background none -gravity center -extent 128x128 "$out"
                fi
                done_flag=1
                break
            fi
        done
    elif [ "$src" = "flatpak" ]; then
        # Экспорт иконки из установленного flatpak-приложения
        for cand in \
            "/var/lib/flatpak/exports/share/icons/hicolor/scalable/apps/${icon}.svg" \
            "/var/lib/flatpak/exports/share/icons/hicolor/512x512/apps/${icon}.png" \
            "/var/lib/flatpak/exports/share/icons/hicolor/256x256/apps/${icon}.png"; do
            if [ -f "$cand" ]; then
                if [[ "$cand" == *.svg ]]; then
                    rsvg-convert -w 128 -h 128 "$cand" -o "$out"
                else
                    magick "$cand" -resize 128x128 \
                        -background none -gravity center -extent 128x128 "$out"
                fi
                done_flag=1
                break
            fi
        done
    else
        # hicolor: крупный растр, затем scalable SVG, затем мелкий (Java — макс 48)
        for cand in \
            "/usr/share/icons/hicolor/256x256/apps/${icon}.png" \
            "/usr/share/icons/hicolor/512x512/apps/${icon}.png" \
            "/usr/share/icons/hicolor/128x128/apps/${icon}.png" \
            "/usr/share/icons/hicolor/scalable/apps/${icon}.svg" \
            "/usr/share/icons/hicolor/256x256@2/apps/${icon}.png" \
            "/usr/share/icons/hicolor/48x48/apps/${icon}.png"; do
            if [ -f "$cand" ]; then
                if [[ "$cand" == *.svg ]]; then
                    rsvg-convert -w 128 -h 128 "$cand" -o "$out"
                else
                    magick "$cand" -resize 128x128 \
                        -background none -gravity center -extent 128x128 "$out"
                fi
                done_flag=1
                break
            fi
        done
    fi

    if [ "$done_flag" = "1" ]; then
        # Подпись под иконкой; \n в TSV → перенос строки в подписи.
        # Иконка прижата к верху клетки (128×160): 32 px прозрачного
        # поля внизу — место, где montage рисует подпись с отступом.
        magick "$out" -background none -gravity north -extent 128x160 \
            -set label "${label//$'\n'/$'\n'}" "$out"
        FOUND=$((FOUND + 1))
    else
        MISSING=$((MISSING + 1))
        echo "ПРОПУЩЕНА: $app ($icon, $src)" >&2
    fi
done < "$WORK/icons.tsv"

echo "Иконок собрано: $FOUND, пропущено: $MISSING"

if [ "$MISSING" -gt 0 ]; then
    echo "Доска собрана с пропусками — проверьте строки выше" >&2
fi

# Перемешанный порядок файлов — иконки не идут по категориям
ls "$WORK/png"/*.png | shuf > "$WORK/order.txt"

# Сетка 12×6 = 72 места под 72 иконки. Клетка 128×160: иконка 128
# вверху, 32 px прозрачного поля внизу — под ним montage рисует
# подпись. Зазор между рядами 8 px — ряды вплотную, подписи не
# слипаются. Если иконок станет больше 72 — увеличить до 12×7 и т.д.
montage @"$WORK/order.txt" \
    -tile 12x6 \
    -geometry 128x160+16+8 \
    -background black \
    -fill white \
    -pointsize 26 \
    -gravity south \
    "$OUT"

identify "$OUT"
