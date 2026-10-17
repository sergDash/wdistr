#!/bin/sh
# Одноразовая доводка Cinnamon до настроек дистрибутива (решение 2026-10-09).
#
# Зачем: при первом входе Cinnamon сам записывает свои дефолты
# (gtk-theme Adwaita, шрифты Adwaita Sans) в пользовательский dconf —
# системный dconf-дефолт (/etc/dconf/db/local.d) он перебивает. Поэтому
# нужные значения ставятся принудительно, но ТОЛЬКО ОДИН РАЗ: маркер
# не даёт скрипту трогать настройки, которые пользователь уже настроил
# сам. Следующий запуск (при следующем входе) завершается сразу.
MARKER="$HOME/.config/wdistr/cinnamon-defaults-done"
[ -f "$MARKER" ] && exit 0

mkdir -p "$HOME/.config/wdistr"

# Тёмная тема: GTK и libadwaita (системный dconf-дефолт держит
# color-scheme, но cinnamon мог перебить и это)
gsettings set org.cinnamon.desktop.interface gtk-theme 'Mint-Y-Dark-Aqua-10'
gsettings set org.gnome.desktop.interface gtk-theme 'Mint-Y-Dark-Aqua-10'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

# Без анимаций: GTK-ключ и effects-путь dconf (модуль «Эффекты»
# настроек Cinnamon; вторая запись — на случай, если схемы нет)
gsettings set org.cinnamon.desktop.interface enable-animations false
gsettings set org.gnome.desktop.interface enable-animations false
dconf write /org/cinnamon/desktop/effects/enable-animations false
# Галочка «Эффекты» в настройках Cinnamon — это отдельный ключ
# корневой схемы org.cinnamon (находка 2026-10-09: GTK-ключ enable-
# animations на неё не влияет, она жива даже при GTK-выключении)
gsettings set org.cinnamon desktop-effects-workspace false

# Шрифты Ubuntu (пакет ttf-ubuntu-font-family): интерфейс, документы,
# моноширинный, заголовок окна, рабочий стол (nemo)
gsettings set org.cinnamon.desktop.interface font-name 'Ubuntu 11'
gsettings set org.gnome.desktop.interface font-name 'Ubuntu 11'
gsettings set org.gnome.desktop.interface document-font-name 'Ubuntu 11'
gsettings set org.gnome.desktop.interface monospace-font-name 'Ubuntu Mono 12'
gsettings set org.cinnamon.desktop.wm.preferences titlebar-font 'Ubuntu Bold 11'
gsettings set org.nemo.desktop font 'Ubuntu 10'

# Заставка, монитор и кнопка питания (решение 2026-10-15): значения
# сняты с рабочей машины. Системный dconf-дефолт (10-wdistr-desktop)
# держит их для свежих пользователей, здесь — тот же паттерн, что
# у тем и шрифтов: при первом входе Cinnamon пишет собственные
# значения в пользовательский dconf, перекрывая системный (опыт
# 2026-10-09), поэтому принудительно один раз. Повторных запусков
# маркер не даёт — настройки, изменённые пользователем, не трогаются.
gsettings set org.cinnamon.desktop.session idle-delay 0
gsettings set org.cinnamon.settings-daemon.plugins.power sleep-display-ac 3600
gsettings set org.cinnamon.settings-daemon.plugins.power button-power 'shutdown'

# Терминал по умолчанию — Ghostty БЕЗ single-instance (решение
# 2026-10-17). При single-instance «Открыть в терминале» из Nemo уходил
# через D-Bus работающему процессу и открывал домашнюю директорию
# вместо папки. Дубль системного dconf-дефолта по паттерну тем/шрифтов:
# cinnamon при первом входе мог перебить значение своим дефолтом.
gsettings set org.cinnamon.desktop.default-applications.terminal exec '/usr/bin/ghostty'

# Съёмные носители: переключатель «Спрашивать или запускать программы
# при подключении носителя» — выключен (autorun-never=true; виджет
# инвертирует ключ, дефолт схемы false). Диалог выбора приложения при
# вставке носителя не показывается. На тестовой 2026-10-15 ключ оказался
# записан в пользовательский dconf отдельно от дефолта — системную
# запись (10-wdistr-desktop) дублируем здесь по паттерну тем/шрифтов;
# отработала или нет — проверить при следующей установке.
gsettings set org.cinnamon.desktop.media-handling autorun-never true

# Высота основного монитора (решение 2026-10-16): >1500 px — 4K и
# выше. На таких экранах увеличиваем панель, масштаб текста и иконку
# меню; на меньших (1080, 1200, 1440) размеры не трогаем — дефолты
# Cinnamon подходят. Порог простой, без диапазонов.
SCREEN_HEIGHT=$(xrandr 2>/dev/null | grep " primary" | sed -n 's/.* connected primary [0-9]*x\([0-9]*\)+.*/\1/p')

# Панель задач: меню и список окон в центральной зоне без разделителя
# (решение 2026-10-16) — это раскладка, применяется ВСЕГДА, независимо
# от высоты. Дубль в dconf-дефолте (10-wdistr-desktop).
gsettings set org.cinnamon enabled-applets "['panel1:center:0:menu@cinnamon.org:0', 'panel1:center:1:grouped-window-list@cinnamon.org:2', 'panel1:right:0:systray@cinnamon.org:3', 'panel1:right:1:xapp-status@cinnamon.org:4', 'panel1:right:2:notifications@cinnamon.org:5', 'panel1:right:3:printers@cinnamon.org:6', 'panel1:right:4:removable-drives@cinnamon.org:7', 'panel1:right:5:keyboard@cinnamon.org:8', 'panel1:right:6:favorites@cinnamon.org:9', 'panel1:right:7:network@cinnamon.org:10', 'panel1:right:8:sound@cinnamon.org:11', 'panel1:right:9:power@cinnamon.org:12', 'panel1:right:10:calendar@cinnamon.org:13', 'panel1:right:11:cornerbar@cinnamon.org:14']"

# Меню «Пуск»: своя иконка без текста — всегда; размер — только на
# больших экранах (см. SCREEN_HEIGHT). Настройки applet'ов Cinnamon
# живут НЕ в dconf, а в JSON-файлах ~/.config/cinnamon/spices/<applet>/<id>.json —
# gsettings сюда не дотягивается. Файл создаёт Cinnamon при загрузке
# applet'а, к моменту autostart он уже есть; подождём до 5 с.
# Патчим только value-поля, схему (type/default/description) не трогаем.
MENU_JSON="$HOME/.config/cinnamon/spices/menu@cinnamon.org/0.json"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$MENU_JSON" ] && break
    sleep 1
done
if [ -f "$MENU_JSON" ]; then
    MENU_SIZE=32
    if [ -n "$SCREEN_HEIGHT" ] && [ "$SCREEN_HEIGHT" -gt 1500 ]; then
        MENU_SIZE=50
    fi
    python3 -c "
import json, pathlib
p = pathlib.Path('$MENU_JSON')
d = json.loads(p.read_text())
d['menu-custom']['value'] = True
d['menu-icon']['value'] = 'cinnamon-symbolic'
d['menu-icon-size']['value'] = $MENU_SIZE
d['menu-label']['value'] = ''
p.write_text(json.dumps(d, indent=4))
"
fi

# Размеры панели и масштаб текста — ТОЛЬКО на экранах выше 1500 px
# (решение 2026-10-16). На дефолтных 1080/1200/1440 эти значения
# мешают работать — Cinnamon оставляет свои дефолты (панель 40,
# масштаб 1.0). Два ключа масштаба: cinnamon читает СВОЙ
# (org.cinnamon.desktop.interface), gnome-ключ ему не подчиняется
# (опыт 2026-10-16: gnome=1.5, cinnamon остался 1.0, текст не вырос).
if [ -n "$SCREEN_HEIGHT" ] && [ "$SCREEN_HEIGHT" -gt 1500 ]; then
    gsettings set org.cinnamon panels-height "['1:60']"
    gsettings set org.cinnamon panel-zone-icon-sizes '[{"panelId": 1, "left": 0, "center": 0, "right": 32}]'
    gsettings set org.cinnamon panel-zone-symbolic-icon-sizes '[{"panelId": 1, "left": 28, "center": 28, "right": 26}]'
    gsettings set org.gnome.desktop.interface text-scaling-factor 1.5
    gsettings set org.cinnamon.desktop.interface text-scaling-factor 1.5
fi

# Календарь: кастомные форматы даты (решение 2026-10-16, значения
# с рабочей машины). Тот же паттерн JSON-патча, что у меню.
# Идентификатор экземпляра 13 фиксирован нашим enabled-applets.
CAL_JSON="$HOME/.config/cinnamon/spices/calendar@cinnamon.org/13.json"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$CAL_JSON" ] && break
    sleep 1
done
if [ -f "$CAL_JSON" ]; then
    python3 -c "
import json, pathlib
p = pathlib.Path('$CAL_JSON')
d = json.loads(p.read_text())
d['use-custom-format']['value'] = True
d['custom-format']['value'] = '%a, %e %b, %H:%M'
d['custom-tooltip-format']['value'] = '%A, %e %B, %H:%M'
p.write_text(json.dumps(d, indent=4))
"
fi

touch "$MARKER"
