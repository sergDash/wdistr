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

# Терминал по умолчанию — Ghostty с ЯВНЫМ --gtk-single-instance=false
# (решение 2026-10-17). При single-instance «Открыть в терминале» из
# Nemo уходил через D-Bus работающему процессу, окно рисовал первичный
# процесс и брало каталог последнего окна вместо папки Nemo. Просто
# убрать =true недостаточно: дефолт gtk-single-instance=detect при
# работающем основном процессе всё равно делегирует ему. Дубль
# системного dconf-дефолта по паттерну тем/шрифтов: cinnamon при
# первом входе мог перебить значение своим дефолтом.
gsettings set org.cinnamon.desktop.default-applications.terminal exec '/usr/bin/ghostty --gtk-single-instance=false'

# Съёмные носители: переключатель «Спрашивать или запускать программы
# при подключении носителя» — выключен (autorun-never=true; виджет
# инвертирует ключ, дефолт схемы false). Диалог выбора приложения при
# вставке носителя не показывается. На тестовой 2026-10-15 ключ оказался
# записан в пользовательский dconf отдельно от дефолта — системную
# запись (10-wdistr-desktop) дублируем здесь по паттерну тем/шрифтов;
# отработала или нет — проверить при следующей установке.
gsettings set org.cinnamon.desktop.media-handling autorun-never true

# Перетаскивание окон — Win, не Alt (решение 2026-10-17, значение с
# рабочей машины). Дубль системного dconf-дефолта: Cinnamon при первом
# входе мог перебить значение своим дефолтом.
gsettings set org.cinnamon.desktop.wm.preferences mouse-button-modifier '<Super>'

# Значки на кнопках окон — выключены (решение 2026-10-17). Ключ
# xsettings-схемы (модуль «Темы»); дубль системного дефолта.
gsettings set org.cinnamon.settings-daemon.plugins.xsettings buttons-have-icons false

# Вид папок по умолчанию — компактный (пожелание 2026-10-23): значение
# с рабочей машины, где вид выбран руками. Дефолт схемы Nemo —
# icon-view; ключ пишется безусловно, независимо от высоты экрана.
# Масштаб этого вида (150% на больших экранах) задан ниже, в блоке
# условия по SCREEN_HEIGHT. Дубль системного dconf-дефолта
# (10-wdistr-desktop) по паттерну тем/шрифтов.
gsettings set org.nemo.preferences default-folder-viewer 'compact-view'

# Высота основного монитора (решение 2026-10-16): >1500 px — 4K и
# выше. На таких экранах увеличиваем панель, масштаб текста и иконку
# меню; на меньших (1080, 1200, 1440) размеры не трогаем — дефолты
# Cinnamon подходят. Порог простой, без диапазонов.
SCREEN_HEIGHT=$(xrandr 2>/dev/null | grep " primary" | sed -n 's/.* connected primary [0-9]*x\([0-9]*\)+.*/\1/p')

# Меню «Пуск»: своя иконка без текста — всегда; размер — только на
# больших экранах (см. SCREEN_HEIGHT). Настройки applet'ов Cinnamon
# живут НЕ в dconf, а в JSON-файлах ~/.config/cinnamon/spices/<applet>/<id>.json —
# gsettings сюда не дотягивается. Файл создаёт Cinnamon при загрузке
# applet'а, к моменту autostart он уже есть; подождём до 5 с.
# Патчим только value-поля, схему (type/default/description) не трогаем.
#
# ПОРЯДОК ВАЖЕН (опыт 2026-10-18, установки user2/user3/user4):
# applet читает JSON при СОЗДАНИИ; «Reloading applet» настройки НЕ
# перечитывает (проверено на user4: перезагрузка в логе, иконка не
# выросла), перенос между зонами — тоже (Cinnamon перемещает applet
# без пересоздания). Надёжное пересоздание — НОВЫЙ instance id:
# список использует menu@cinnamon.org:5, и перед сменой списка копия
# пропатченного 0.json кладётся в 5.json — свежий instance читает
# готовый файл с первого входа. Экземпляр 5 закрепится в dconf,
# дальше applet сам ведёт 5.json; нулевой (дефолтный) после смены
# списка выгружается, его файл остаётся без дела.
MENU_JSON="$HOME/.config/cinnamon/spices/menu@cinnamon.org/0.json"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$MENU_JSON" ] && break
    sleep 1
done
if [ -f "$MENU_JSON" ]; then
    MENU_SIZE=32
    BIG_SCREEN=0
    if [ -n "$SCREEN_HEIGHT" ] && [ "$SCREEN_HEIGHT" -gt 1500 ]; then
        MENU_SIZE=50
        BIG_SCREEN=1
    fi
    python3 -c "
import json, pathlib
p = pathlib.Path('$MENU_JSON')
d = json.loads(p.read_text())
d['menu-custom']['value'] = True
d['menu-icon']['value'] = 'cinnamon-symbolic'
d['menu-icon-size']['value'] = $MENU_SIZE
d['menu-label']['value'] = ''
# Полноразмерные иконки категорий вместо символьных (пожелание
# 2026-10-20)
d['symbolic-category-icons']['value'] = False
# Иконки боковой панели меню — 32 px (пожелание 2026-10-20, дефолт 24)
d['sidebar-icon-size']['value'] = 32
# Размеры иконок категорий и приложений — увеличиваем только на
# больших экранах (пожелание 2026-10-20); на дефолтных 1080/1200/1440
# остаются дефолты Cinnamon (16 и 32)
if $BIG_SCREEN:
    d['category-icon-size']['value'] = 32
    d['application-icon-size']['value'] = 48
p.write_text(json.dumps(d, indent=4))
"
    # Копия для instance 5 — читается при пересоздании (см. выше)
    cp "$MENU_JSON" "$HOME/.config/cinnamon/spices/menu@cinnamon.org/5.json"
fi

# Панель задач: меню и список окон в центральной зоне без разделителя
# (решение 2026-10-16) — это раскладка, применяется ВСЕГДА, независимо
# от высоты. Дубль в dconf-дефолте (10-wdistr-desktop). Instance меню —
# 5 (см. комментарий выше): закрепляет пересоздание applet'а с
# готовым размером иконки.
gsettings set org.cinnamon enabled-applets "['panel1:center:0:menu@cinnamon.org:5', 'panel1:center:1:grouped-window-list@cinnamon.org:2', 'panel1:right:0:systray@cinnamon.org:3', 'panel1:right:1:xapp-status@cinnamon.org:4', 'panel1:right:2:notifications@cinnamon.org:5', 'panel1:right:3:printers@cinnamon.org:6', 'panel1:right:4:removable-drives@cinnamon.org:7', 'panel1:right:5:keyboard@cinnamon.org:8', 'panel1:right:6:favorites@cinnamon.org:9', 'panel1:right:7:network@cinnamon.org:10', 'panel1:right:8:sound@cinnamon.org:11', 'panel1:right:9:power@cinnamon.org:12', 'panel1:right:10:calendar@cinnamon.org:13', 'panel1:right:11:cornerbar@cinnamon.org:14']"

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
    # Nemo, компактный вид: исходный масштаб 150% (пожелание 2026-10-23,
    # значение с рабочей машины). «Исходный масштаб» в настройках и меню
    # Nemo — это default-zoom-level; проценты в меню соответствуют
    # уровням enum smallest..largest = 33/50/66/100/150/200/400, то
    # есть 150% — это 'large'. Ключ условный, как у панели и масштаба
    # текста: на экранах ≤1500 остаётся дефолт схемы 'standard' (100%).
    gsettings set org.nemo.compact-view default-zoom-level large
fi

# Календарь: кастомные форматы даты (решение 2026-10-16, значения
# с рабочей машины). Тот же паттерн JSON-патча, что у меню.
# Идентификатор экземпляра 13 фиксирован нашим enabled-applets.
# Дубль посева: 13.json доставляется custom_commands (опыт
# 2026-10-18: на чистой установке applet создавал файл с дефолтами
# уже после патча — формат не применялся до второго входа; посев
# даёт готовый файл до первой загрузки applet'а).
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

# Группировка окон на панели отменена (решение 2026-10-17, значение с
# рабочей машины): каждое окно — отдельной кнопкой, без группировки по
# программе. Тот же JSON-паттерн, что у меню и календаря; идентификатор
# экземпляра 2 задан нашим enabled-applets.
GWL_JSON="$HOME/.config/cinnamon/spices/grouped-window-list@cinnamon.org/2.json"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$GWL_JSON" ] && break
    sleep 1
done
if [ -f "$GWL_JSON" ]; then
    python3 -c "
import json, pathlib
p = pathlib.Path('$GWL_JSON')
d = json.loads(p.read_text())
d['group-apps']['value'] = False
p.write_text(json.dumps(d, indent=4))
"
fi

touch "$MARKER"
