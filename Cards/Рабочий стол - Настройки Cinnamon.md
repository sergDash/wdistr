type: инструкция
category: wdistr/Рабочий стол
title: Рабочий стол — настройки Cinnamon (панель и дальше)
summary:
  Настройки Cinnamon, которые дистрибутив ставит по умолчанию: панель
  задач (центральная зона, размеры), тема, шрифты, поведение рабочего
  стола. Механизм двухслойный: системный dconf-дефолт + одноразовый
  скрипт первого входа. Карточка пополняется по мере добавления
  настроек.
date: 2026-10-16

## Механизм доставки

Настройки рабочего стола живут в двух местах (паттерн 2026-10-09,
уточнён 2026-10-15):

1. **Системный dconf-дефолт** — `install/files/dconf-local-desktop`
   (`/etc/dconf/db/local.d/10-wdistr-desktop`). Действует на всех
   свежих пользователей: до первого входа в сессию у них нет
   пользовательского dconf, и система читает дефолт.
2. **Одноразовый скрипт первого входа** —
   `install/files/cinnamon-defaults.sh` (`/usr/local/bin/wdistr-cinnamon-defaults`,
   автозапуск через `/etc/xdg/autostart/wdistr-cinnamon-defaults.desktop`).
   При первом входе Cinnamon сам записывает свои дефолты (GTK-тему,
   шрифты, панель) в пользовательский dconf, перекрывая системный
   дефолт. Скрипт принудительно ставит наши значения, но **только один
   раз**: маркер `~/.config/wdistr/cinnamon-defaults-done` не даёт
   ему трогать настройки, которые пользователь уже изменил сам.

Оба файла правятся синхронно: одно и то же значение — в dconf-дефолт
и в gsettings-команду скрипта. После правки —
`python3 install/regen-custom-commands.py`.

**Не перезапускать cinnamon командами** (`cinnamon --replace`, `killall
cinnamon`) — не слушается, сессия может зависнуть (замечание
пользователя 2026-10-16). Перезапуск сессии — руками пользователем.

## Панель задач

Решение 2026-10-16: меню «Пуск» и список окон — в центральной зоне
панели, без разделителя между ними. На рабочей машине панель была
настроена так руками; в дистрибутив перенесена как дефолт.

**Раскладка vs размеры.** Раскладка (`enabled-applets`) применяется
всегда. Размеры (высота панели, размеры иконок, масштаб текста,
размер иконки меню) — только при высоте основного монитора **более
1500 px** (решение 2026-10-16). Порог отсеивает 4K-диски (2160) от
стандартных (1080, 1200, 1440); на стандартных дефолты Cinnamon
подходят, увеличение мешает работать. Высота определяется по
основному монитору из `xrandr`; проверка — в `cinnamon-defaults.sh`.
dconf-дефолт условий не умеет — размеры в нём НЕТ, только раскладка.

| Ключ | Значение | Когда |
|---|---|---|
| `enabled-applets` | menu + grouped-window-list в `center`, остальные в `right` | всегда (раскладка) |
| `panels-height` | `['1:60']` | высота > 1500 |
| `panel-zone-icon-sizes` | right: 32 | высота > 1500 |
| `panel-zone-symbolic-icon-sizes` | left: 28, center: 28, right: 26 | высота > 1500 |
| `text-scaling-factor` (gnome + cinnamon) | `1.5` | высота > 1500 |

Формат `enabled-applets` — массив строк вида
`panel<номер>:<зона>:<порядок>:<applet-id>:<id>`. Зона — `left`,
`center` или `right`. Порядок — позиция внутри зоны (с нуля). Id —
внутренний идентификатор экземпляра applet, при удалении не
переиспользуется (следующий свободный — `next-applet-id`).

Значения в dconf-дефолте (`10-wdistr-desktop`):

```
[org/cinnamon]
enabled-applets=['panel1:center:0:menu@cinnamon.org:0', 'panel1:center:1:grouped-window-list@cinnamon.org:2', 'panel1:right:0:systray@cinnamon.org:3', 'panel1:right:1:xapp-status@cinnamon.org:4', 'panel1:right:2:notifications@cinnamon.org:5', 'panel1:right:3:printers@cinnamon.org:6', 'panel1:right:4:removable-drives@cinnamon.org:7', 'panel1:right:5:keyboard@cinnamon.org:8', 'panel1:right:6:favorites@cinnamon.org:9', 'panel1:right:7:network@cinnamon.org:10', 'panel1:right:8:sound@cinnamon.org:11', 'panel1:right:9:power@cinnamon.org:12', 'panel1:right:10:calendar@cinnamon.org:13', 'panel1:right:11:cornerbar@cinnamon.org:14']
panels-height=['1:60']
panel-zone-icon-sizes=[{'panelId': 1, 'left': 0, 'center': 0, 'right': 32}]
panel-zone-symbolic-icon-sizes=[{'panelId': 1, 'left': 28, 'center': 28, 'right': 26}]
```

Тот же набор в `cinnamon-defaults.sh` — командами `gsettings set`.

## Тема и шрифты

| Ключ | Значение |
|---|---|
| `gtk-theme` (cinnamon + gnome) | `Mint-Y-Dark-Aqua-10` |
| `color-scheme` (gnome) | `prefer-dark` |
| `font-name` | `Ubuntu 11` |
| `text-scaling-factor` (gnome + cinnamon) | `1.5` | Ubuntu 11 рендерится ~16.5 px; только при высоте > 1500 (см. «Панель задач») |
| `monospace-font-name` | `Ubuntu Mono 12` |
| `titlebar-font` | `Ubuntu Bold 11` |
| `nemo font` | `Ubuntu 10` |

## Меню «Пуск»

Настройки applet'ов Cinnamon живут **не в dconf**, а в JSON-файлах
`~/.config/cinnamon/spices/<applet-id>/<instance-id>.json`. Файл
создаёт Cinnamon при загрузке applet'а; gsettings сюда не дотягивается —
патчить нужно python'ом, меняя только `value`-поля (схему
type/default/description не трогать).

Ключи меню (`menu@cinnamon.org/0.json`):

| Ключ | Значение | Смысл |
|---|---|---|
| `menu-custom` | `true` | «Использовать свою иконку и подпись» — галка, без неё размер/иконка/текст не применяются; всегда |
| `menu-icon` | `cinnamon-symbolic` | иконка меню; всегда |
| `menu-icon-size` | `50` (> 1500 px) или `32` (дефолт) | размер иконки в px |
| `menu-label` | `""` | пустая строка — текста на панели нет; всегда |
| `symbolic-category-icons` | `false` | полноразмерные иконки категорий вместо символьных; всегда (пожелание 2026-10-20) |
| `sidebar-icon-size` | `32` | иконки боковой панели меню в px (дефолт 24); всегда (пожелание 2026-10-20) |
| `category-icon-size` | `32` (> 1500 px) | размер иконок категорий в меню (дефолт 16); на дефолтных экранах не трогаем |
| `application-icon-size` | `48` (> 1500 px) | размер иконок приложений в меню (дефолт 32); на дефолтных экранах не трогаем |

Патч в `cinnamon-defaults.sh` — python-блок после ожидания файла
(до 5 с: autostart и загрузка applet'а идут параллельно). Cinnamon
подхватывает JSON только при (пере)загрузке applet'а — на первом
входе это происходит естественно.

## Календарь

Кастомные форматы даты (решение 2026-10-16, значения с рабочей
машины). Тот же JSON-паттерн, что у меню; файл —
`calendar@cinnamon.org/13.json` (id 13 фиксирован нашим
enabled-applets).

| Ключ | Значение | Смысл |
|---|---|---|
| `use-custom-format` | `true` | галка «кастомный формат» — без неё форматы не применяются |
| `custom-format` | `%a, %e %b, %H:%M` | на панели: «ср, 15 окт, 14:30» |
| `custom-tooltip-format` | `%A, %e %B, %H:%M` | во всплывающей подсказке: «среда, 15 октября, 14:30» |

## Программы по умолчанию (mimeapps.list)

Системный файл `install/files/xdg-mimeapps.list` → `/etc/xdg/mimeapps.list`
(доставка custom_commands). Действует на всех пользователей; выбор
пользователя в `~/.config/mimeapps.list` его перекрывает — это
ожидаемо. Ассоциации сняты с рабочей машины (решение 2026-10-16).

| Категория Cinnamon | Программа | Ключевые MIME-типы |
|---|---|---|
| Интернет.Сеть | Firefox | `x-scheme-handler/http(s)` — дефолт, не прописан |
| Интернет.Почта | Thunderbird (`org.mozilla.Thunderbird.desktop`) | `mailto`, `message/rfc822`, `text/calendar` |
| Мультимедия.Фото | Viewnior | `image/*` (bmp, gif, jpeg, png, svg, tiff, webp и др.) |
| Офис.Текст | WordCraft (`ai.storyteller.wordcraft.desktop`) | `application/msword`, `.docx`, `.odt`, `.rtf` |
| Офис.Таблица | GridCraft (`ai.storyteller.gridcraft.desktop`) | `.xlsx`, `.ods`, `text/csv` |
| Офис.PDF | Okular (`okularApplication_pdf.desktop`) | `application/pdf` |
| Папки | Nemo | `inode/directory` |
| — (не категория Cinnamon) | VectorCraft (`ai.storyteller.vectorcraft.desktop`) | `application/illustrator` — `.ai` (пожелание 2026-10-23; тип даёт глоб freedesktop, .desktop VectorCraft его не объявляет) |

Имена .desktop-файлов: Thunderbird в Arch — `org.mozilla.Thunderbird.desktop`
(не `thunderbird.desktop`); Okular PDF — `okularApplication_pdf.desktop`
(отдельный PDF-хендлер); Craft-пакеты — `ai.storyteller.*.desktop`.

## Автозапуск

Системный автозапуск — `/etc/xdg/autostart/*.desktop`. Свои файлы
доставляются из `install/files/autostart/` через custom_commands
(решение 2026-10-16, паттерн `files/desktop/`): новый файл просто
кладётся в папку, правка regen-скрипта не нужна.

| Программа | Источник автозапуска |
|---|---|
| AmneziaVPN | наш файл `files/autostart/AmneziaVPN.desktop` (пакет не ставит) |
| CopyQ | наш файл `files/autostart/copyq.desktop` (пакет не ставит; задержка 3 с — воркрайд для трея) |
| Emote | пакет AUR ставит сам (`/etc/xdg/autostart/emote.desktop`) |
| Sticky | пакет extra ставит сам (`sticky.desktop` с `--autostart`) |
| Solaar | на рабочей машине в пользовательском автозапуске — в дистрибутив НЕ добавлен (пока не решено) |

## Поведение рабочего стола

| Ключ | Значение | Смысл |
|---|---|---|
| `idle-delay` | `0` | заставка никогда не запускается |
| `sleep-display-ac` | `3600` | монитор гаснет через час простоя |
| `button-power` | `shutdown` | кнопка питания — выключение |
| `enable-animations` | `false` | без анимаций (GTK + effects) |
| `autorun-never` | `true` | диалог автозапуска при подключении носителя не показывается |

## Как добавить новую настройку

1. Снять значение с рабочей машины: `gsettings get <схема> <ключ>`
   или `dconf read /путь/к/ключу`.
2. Добавить в `install/files/dconf-local-desktop` (секция схемы).
3. Добавить в `install/files/cinnamon-defaults.sh` (команда
   `gsettings set` с комментарием — зачем и откуда значение).
4. Прогнать `python3 install/regen-custom-commands.py`.
5. Пополнить таблицу в этой карточке.
