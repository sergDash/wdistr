type: инструкция
category: wdistr/Рабочий стол
title: Steam — своя иконка игры на панели Cinnamon вместо иконки Steam
summary:
  Игра, запущенная через Flatpak-Steam, на панели Cinnamon показывает
  иконку Steam, а не свою. Причина: WM_CLASS окна игры (steam_app_<appid>)
  не совпадает ни с одним .desktop-файлом, и окно привязывается к
  процессу Steam. Лечится созданием .desktop-файла с StartupWMClass и
  иконкой, извлечённой из exe игры утилитой wrestool (пакет icoutils).
date: 2026-10-17

## Симптом

Запущены Steam и игра. На панели у обоих окон — иконка Steam. У окна
игры при этом есть собственная иконка (`_NET_WM_ICON` через `xprop`),
но панель её не использует.

## Диагноз: как определить WM_CLASS окна

Панель (applet `grouped-window-list`) определяет иконку так: берёт
`WM_CLASS` окна и ищет `.desktop`-файл с совпадающим `StartupWMClass`
(или именем файла). Если совпадения нет — окно привязывается к
родительскому процессу (у игры это Steam в той же Flatpak-песочнице)
и получает его иконку.

Чтобы выяснить `WM_CLASS` проблемного окна, выполняется обход всех
клиентских окон X-сервера:

```fish
xprop -root _NET_CLIENT_LIST_STACKING | grep -oE '0x[0-9a-f]+' | while read id
    cls=$(xprop -id "$id" WM_CLASS 2>/dev/null)
    case "$cls" in
        *steam*|*244850*)
            echo "=== $id $cls"
            xprop -id "$id" _NET_WM_NAME _NET_WM_PID
            ;;
    end
end
```

`_NET_CLIENT_LIST_STACKING` — список окон в порядке поднятия (сверху
вниз). Для каждого извлекается `WM_CLASS`, `WM_NAME` (заголовок) и
`_NET_WM_PID`. Фильтр `*steam*` отсекает посторонние окна; если ищется
конкретная игра — по аппиду Steam (`*<appid>*`).

Пример вывода для Space Engineers (appid 244850):

```
WM_CLASS(STRING) = "steam_app_244850", "steam_app_244850"
_NET_WM_NAME(UTF8_STRING) = "Space Engineers"
_NET_WM_PID(CARDINAL) = 7743
```

Обе части `WM_CLASS` (instance и class) одинаковы — `steam_app_244850`.
Это значение и есть ключ к решению: оно должно совпасть с
`StartupWMClass` в .desktop-файле.

Для сравнения, окно клиента Steam:

```
WM_CLASS(STRING) = "steamwebhelper", "steam"
```

У него `StartupWMClass=Steam` в штатном `com.valvesoftware.Steam.desktop` —
совпадение есть, иконка правильная.

## Решение: .desktop-файл с StartupWMClass

Файл кладётся в `~/.local/share/applications/steam_app_<appid>.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=Space Engineers
Exec=/usr/bin/flatpak run com.valvesoftware.Steam steam://rungameid/244850
Icon=steam_app_244850
StartupWMClass=steam_app_244850
Terminal=false
Categories=Game;
```

| Ключ | Значение | Смысл |
|---|---|---|
| `StartupWMClass` | `steam_app_244850` | должен точно совпасть с `WM_CLASS` окна игры — иначе панель не найдёт файл |
| `Icon` | `steam_app_244850` | имя иконки без расширения; GTK ищет по имени в теме (см. ниже) |
| `Exec` | `flatpak run ... steam://rungameid/<appid>` | запуск через Flatpak-Steam; имя файла игры для `rungameid` — appid |
| имя файла | `steam_app_244850.desktop` | applet панели сначала ищет .desktop по имени (= WM_CLASS); совпадение имени — достаточное условие, `StartupWMClass` — страховка |

После создания файла — обновить базу desktop-файлов:

```fish
update-desktop-database ~/.local/share/applications
```

Затем перезапустить панель: **Alt+F2 → `r` → Enter** (Cinnamon
перезапускается, открытые окна не закрываются). Если игра в фуллскрине
и перехватывает клавиши — сначала закрыть игру, перезапустить Cinnamon,
запустить игру заново.

## Иконка: куда класть и что не нужно

Иконка ищется GTK по имени `steam_app_244850` (без расширения) в
каталогах темы иконок. Кладётся в пользовательский hicolor:

```
~/.local/share/icons/hicolor/256x256/apps/steam_app_244850.png
```

Формат пути: `hicolor/<размер>x<размер>/apps/<имя>.png`. Размер берётся
256×256 — этого хватает и для панели (обычно 22–32 px), и для HiDPI
(GTK уменьшает при необходимости).

**Файл `index.theme` НЕ нужен.** Пользовательский каталог
`~/.local/share/icons/hicolor/` работает без него: GTK ищет иконки
по структуре каталогов `<размер>/apps/`, индексный файл строить не
требуется. Попытка `gtk-update-icon-cache -f` на пустом hicolor падает
с «No theme index file» — это нормально, кэш не нужен.

Проверка, что GTK находит иконку:

```fish
python3 -c "
import gi
gi.require_version('Gtk','3.0')
from gi.repository import Gtk
t = Gtk.IconTheme.get_default()
i = t.lookup_icon('steam_app_244850', 256, 0)
print('icon found:', i.get_filename() if i else None)
"
```

## Извлечение иконки из exe: пакет icoutils

Windows-игры хранят иконку внутри .exe (ресурс ICO). Извлекается
двумя утилитами из пакета **`icoutils`** (extra):

```fish
sudo pacman -S icoutils
```

1. `wrestool` — извлекает ICO из PE-файла:

   ```fish
   wrestool -x -t 14 -o /tmp/se-icon/ /путь/к/игре/Game.exe
   ```

   `-t 14` — тип ресурса «иконка» (RT_ICON). На выходе — `.ico` с
   набором размеров.

2. `icotool` — смотрит содержимое и извлекает конкретный размер:

   ```fish
   icotool -l icon.ico          # список: размеры, глубина
   icotool -x -i 5 icon.ico     # извлечь иконку с индексом 5
   ```

   В Space Engineers в ico нашлись размеры до 256×256 (32 бита, с
   альфой); индекс 5 соответствует 256×256×32. На выходе — PNG.

3. Полученный PNG кладётся в `~/.local/share/icons/hicolor/256x256/apps/steam_app_<appid>.png`.

Путь к exe игры: `~/.../SteamLibrary/steamapps/common/<Название>/...`
(у Space Engineers — `Bin64/SpaceEngineers.exe`). Путь к Steam-кэшу с
готовой маленькой иконкой (32×32, если извлекать не нужно):
`~/.var/app/com.valvesoftware.Steam/.local/share/Steam/appcache/librarycache/<appid>/`.

## Почему «Добавить ярлык на рабочем столе» из Steam не работает

ПКМ по игре → «Управление» → «Добавить ярлык на рабочем столе» в
Flatpak-Steam пишет ярлык внутрь своей песочницы
(`~/.var/app/com.valvesoftware.Steam/Desktop/`), а не в
`~/.local/share/applications` хоста. Оттуда панель хоста его не
подхватывает. Ручное создание .desktop-файла в `~/.local/share/applications`
— обходной путь, работающий без оглядки на песочницу.

## Для дистрибутива

- **Пакет `icoutils`** — добавить в `packages[]` конфига archinstall
  (для извлечения иконок из exe при изготовлении .desktop-файлов;
  строка в `Cards/Базовый набор программ.md` — extra, конфиг).
- **Файлы складируются в `install/files/`** по структуре,
  повторяющей целевую (`~/.local` пользователя):

  | В проекте | Куда уезжает на целевой системе |
  |---|---|
  | `install/files/.local/share/applications/steam_app_<appid>.desktop` | `~/.local/share/applications/` (источник, зеркало домашней папки) |
  | `install/files/.local/share/icons/hicolor/256x256/apps/steam_app_<appid>.png` | `~/.local/share/icons/hicolor/256x256/apps/` (источник, зеркало домашней папки) |
  | `install/files/desktop/steam_app_<appid>.desktop` | `/usr/share/applications/` (доставка custom_commands, паттерн `files/desktop/`) |

  `.desktop`-файл лежит в двух местах намеренно:
  `.local/share/applications/` — исходное зеркало (откуда брали и куда
  клали на рабочей машине), `desktop/` — через него файл реально
  доставляется в систему (regen-custom-commands.py гоняет всё из
  `files/desktop/` в `/usr/share/applications`). Доставка иконки в
  системный hicolor настраивается отдельной строкой в
  `regen-custom-commands.py` (паттерна для `files/.local/` там пока нет).
