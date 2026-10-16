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

## Панель задач

Решение 2026-10-16: меню «Пуск» и список окон — в центральной зоне
панели, без разделителя между ними. На рабочей машине панель была
настроена так руками; в дистрибутив перенесена как дефолт.

| Ключ | Значение | Смысл |
|---|---|---|
| `enabled-applets` | menu + grouped-window-list в `center`, остальные в `right` | левая зона пуста, разделитель убран |
| `panels-height` | `['1:60']` | высота панели 60 px (дефолт Cinnamon — 40) |
| `panel-zone-icon-sizes` | right: 32 | размер цветных иконок в правой зоне |
| `panel-zone-symbolic-icon-sizes` | left: 28, center: 28, right: 26 | размер символических иконок |

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
| `text-scaling-factor` (gnome) | `1.5` — Ubuntu 11 рендерится ~16.5 px; TODO: проверка высоты экрана >1500 |
| `monospace-font-name` | `Ubuntu Mono 12` |
| `titlebar-font` | `Ubuntu Bold 11` |
| `nemo font` | `Ubuntu 10` |

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
