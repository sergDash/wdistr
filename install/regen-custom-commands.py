#!/usr/bin/env python3
"""Пересобирает custom_commands в install/archinstall-config.json.

Файловые настройки живут в install/files/ как исходники; здесь они
кодируются в base64. Так archinstall пишет каждую команду в скрипт
и выполняет его внутри целевой системы, поэтому кавычки и знаки $
в содержимом файлов не интерпретируются по пути.

Правило: после любой правки install/files/* или mirrors.txt запустить:
    python3 install/regen-custom-commands.py
и скопировать конфиг в профиль:
    cp install/archinstall-config.json iso/airootfs/root/wdistr/
(этот шаг делает скрипт автоматически — проверить вывод)."""

import base64
import gzip
import json
import pathlib
import shutil
import struct

INSTALL = pathlib.Path(__file__).resolve().parent
CONFIG = INSTALL / "archinstall-config.json"
FILES = INSTALL / "files"
PROFILE_COPY = INSTALL.parent / "iso/airootfs/root/wdistr/archinstall-config.json"

# Единый список зеркал дистрибутива (решение 2026-10-08; цель —
# одноразовая доставка с 2026-10-15): живая среда работает со списком
# через хук, устанавливаемая получает его при установке один раз и
# дальше живёт своими правками (mirrorlist — backup-файл pacman).
# Отсюда список раздаётся в профиль ISO (живая среда) и в
# custom_commands (целевая система).
MIRRORS = INSTALL.parent / "mirrors.txt"
MIRROR_HOOK = FILES / "wdistr-mirrors.hook"
PROFILE_MIRRORLIST = INSTALL.parent / "iso/airootfs/usr/local/share/wdistr/mirrorlist"
PROFILE_MIRROR_HOOK = INSTALL.parent / "iso/airootfs/etc/pacman.d/hooks/wdistr-mirrors.hook"
# gai.conf: приоритет IPv4 перед IPv6 (хук на glibc — опыт 2026-10-15)
GAI_HOOK = FILES / "wdistr-gai.hook"
PROFILE_GAI_HOOK = INSTALL.parent / "iso/airootfs/etc/pacman.d/hooks/wdistr-gai.hook"
# emote: отключение автозапуска (хук на пакет emote — решение 2026-10-17)
EMOTE_HOOK = FILES / "wdistr-emote.hook"
# ghostty: --gtk-single-instance=false в .desktop (хук на пакет ghostty,
# решение 2026-10-17) — чинит отображение терминала в настройках
# Cinnamon: список терминалов сверяет dconf-ключ exec со строкой Exec
# .desktop, а штатный файл пакета несёт =true
GHOSTTY_HOOK = FILES / "wdistr-ghostty.hook"
PROFILE_GHOSTTY_HOOK = INSTALL.parent / "iso/airootfs/etc/pacman.d/hooks/wdistr-ghostty.hook"


def deliver(src: pathlib.Path, dest: str, mode: str | None = None, compress: bool = False) -> str:
    """Команда доставки файла src в dest целевой системы.
    compress=True — gzip перед base64 (для крупных файлов вроде keymap)."""
    raw = src.read_bytes()
    if compress:
        payload = base64.b64encode(gzip.compress(raw)).decode()
        reader = "base64 -d | gzip -d"
    else:
        payload = base64.b64encode(raw).decode()
        reader = "base64 -d"
    cmd = f"mkdir -p $(dirname {dest}) && echo '{payload}' | {reader} > {dest}"
    if mode:
        cmd += f" && chmod {mode} {dest}"
    return cmd


def main() -> None:
    config = json.loads(CONFIG.read_text())

    # Зеркала: в mirrors.txt — просто URL построчно, этого списка
    # достаточно для archinstall (mirror_regions — массив голых URL), но
    # самому pacman нужен файл вида 'Server = <url>', а локальному
    # парсеру зеркал archinstall (--offline) — заголовок региона
    # '## wdistr': имя региона в файле обязано совпадать с ключом
    # mirror_regions, иначе get_status_by_region падает по KeyError
    # (опыт 2026-10-08: без заголовка сервера уходили в 'Local' и
    # установка вставала). Страна в заголовке не нужна — регион наш,
    # по-русски описываем его обычной строкой комментария (не '## ').
    # Генерируем mirrorlist и кладём в профиль ДО сборки custom_commands:
    # команды доставки кодируют содержимое файла, поэтому файл должен быть
    # готов заранее. Строки с # — комментарии-обоснования в списке,
    # в mirrorlist и mirror_regions они не идут (опыт 2026-10-13:
    # без фильтра комментарий превращался в битую строку Server).
    urls = [
        line.strip()
        for line in MIRRORS.read_text().splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    PROFILE_MIRRORLIST.parent.mkdir(parents=True, exist_ok=True)
    PROFILE_MIRRORLIST.write_text(
        "# Наш статический список хороших серверов: состав закрыт,\n"
        "# правится только файлом mirrors.txt в репозитории.\n"
        "## wdistr\n" + "".join(f"Server = {url}\n" for url in urls)
    )
    config["mirror_config"]["mirror_regions"] = {"wdistr": urls}

    config["custom_commands"] = [
        # multilib: конфиг archinstall включить его сам не умеет
        "sed -i '/#\\[multilib\\]/,/^#Include/ s/^#//' /etc/pacman.conf",
        # Зеркала wdistr (mirrors.txt → mirrorlist): в цель —
        # одноразовая доставка списка, наш дефолт «поставил и работает».
        # Хук с источником в цель НЕ идёт (решение 2026-10-15): у
        # pacman-mirrorlist mirrorlist — backup-файл, правки пользователя
        # переживают обновления пакета сами (новый сток уходит в
        # .pacnew), а хук только перебивал бы их. Хук с источником
        # остаётся в живой среде: там при сборке pacman-mirrorlist
        # свежеустанавливается и затирает список
        deliver(PROFILE_MIRRORLIST, "/etc/pacman.d/mirrorlist"),
        # gai.conf: приоритет IPv4 (precedence ::ffff:0:0/96 100). Без
        # него glibc выбирает IPv6 первым и на виснущем IPv6 соединения
        # ждут таймаута (опыт 2026-10-15: DNS висел 10-14 с, сборки
        # падали). Хук ставится и в цель — для будущих обновлений glibc;
        # строка добавляется сразу, хук — страховка (glibc может
        # перестроить файл при обновлении). grep с ^[^#]: стоковый файл
        # содержит закомментированный пример, наивный grep -q его
        # находит и echo пропускается (опыт чистой установки 2026-10-16)
        deliver(GAI_HOOK, "/etc/pacman.d/hooks/wdistr-gai.hook"),
        "grep -qE '^[^#]*precedence ::ffff:0:0/96' /etc/gai.conf "
        "|| echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf",
        # VirtualBox: обход апстрим-бага #397 (сегфолт VirtualBoxVM при
        # пробуждении/гашении экрана хоста — use-after-free в
        # UIDesktopWidgetWatchdog). Переменная должна быть в окружении
        # VBoxSVC: он порождает VirtualBoxVM и наследует окружение
        # первого приложения, дёргающего API (GUI из меню или VBoxManage
        # из терминала). /etc/environment — потому что его читает pam_env
        # при ЛЮБОМ входе (GUI-сессия, SSH, оболочки), в отличие от
        # profile.d, который GUI-запуск не покрывает. Идемпотентно:
        # grep перед append, чужое значение не перетирается. Детали и
        # стек — Cards/VM - Управление консолью, раздел «Инциденты».
        "grep -q '^VBOX_DESKTOPWATCHDOGPOLICY_SYNTHTEST=' /etc/environment "
        "|| echo 'VBOX_DESKTOPWATCHDOGPOLICY_SYNTHTEST=Disabled' >> /etc/environment",
        # emote: автозапуск отключается хуком ПОСЛЕ установки пакета —
        # сам пакет AUR при установке/обновлении кладёт свой
        # /etc/xdg/autostart/emote.desktop, окно при входе лишнее
        # (подтверждение пользователя 2026-10-17). Хук идёт в цель:
        # emote ставится в first-boot через yay, хук должен уже стоять
        deliver(EMOTE_HOOK, "/etc/pacman.d/hooks/wdistr-emote.hook"),
        # ghostty: --gtk-single-instance=false в .desktop пакета. Штатный
        # файл несёт =true, из-за чего в настройках Cinnamon «Терминал»
        # ghostty не отмечен: список сверяет dconf-ключ exec со строкой
        # Exec .desktop (cs_default.py), а значения не совпадают (опыт
        # 2026-10-17). Хук идёт в цель — для будущих обновлений ghostty;
        # sed выполняется сразу, потому что сам пакет уже установлен
        # archinstall'ом до custom_commands (паттерн gai: хук +
        # немедленное действие)
        deliver(GHOSTTY_HOOK, "/etc/pacman.d/hooks/wdistr-ghostty.hook"),
        "sed -i 's/--gtk-single-instance=true/--gtk-single-instance=false/' "
        "/usr/share/applications/com.mitchellh.ghostty.desktop",
        # Системный дефолт Ghostty (решение 2026-10-17): рамка окна
        # родная (server), цветовые схемы, хоткеи и шрифты — как на
        # рабочей машине. Пользовательский ~/.config/ghostty/config
        # перекрывает
        deliver(FILES / "ghostty/config", "/etc/xdg/ghostty/config"),
        # Системная рамка окна у craft-приложений (решение 2026-10-17):
        # photocraft/vectorcraft по умолчанию рисуют свою (CSD), опция
        # systemTitleBar переключает на системную. Настройка живёт в
        # пользовательском конфиге; минимальный файл приложение само
        # дополняет дефолтами при первом запуске (проверено 2026-10-17).
        # Пишется ДО установки пакетов (она — в first-boot), guard
        # защищает от затирания при повторе setup-continue. Скрипт
        # обёрнут в {...} группы: без них цепочка || при пустом $U
        # создала бы файл в /home/.config (опасный путь)
        "U=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}') && "
        "test -n \"$U\" && "
        "mkdir -p /home/$U/.config/photocraft /home/$U/.config/vectorcraft && "
        "{ test -f /home/$U/.config/photocraft/preferences.json || "
        "echo '{\"interface\":{\"systemTitleBar\":true}}' > /home/$U/.config/photocraft/preferences.json; } && "
        "{ test -f /home/$U/.config/vectorcraft/ui.json || "
        "echo '{\"engine_prefs\":{\"systemTitleBar\":true}}' > /home/$U/.config/vectorcraft/ui.json; } && "
        "chown -R $U:$U /home/$U/.config/photocraft /home/$U/.config/vectorcraft",
        # systemd-resolved — локальный кэширующий резолвер (опыт
        # 2026-10-16 на рабочей машине: кэш убирает зависимость от
        # нестабильного туннеля, повторные имена из памяти за 3 мс).
        # Сам сервис включается через services[]; NetworkManager 1.58+
        # сам передаёт DNS в resolved (проверено) — правка
        # NetworkManager.conf не нужна.
        # Симлинк resolv.conf → stub сюда НЕ СТАВИМ: custom_commands
        # идут через arch-chroot, а он bind-монтирует /etc/resolv.conf
        # хоста поверх /mnt/etc/resolv.conf на время команды (нужен ей
        # для DNS) — «ln -sf» пытается заменить точку монтирования и
        # всегда падает с «Device or resource busy» (опыт установки
        # 2026-10-16). Симлинк ставит setup-continue после archinstall,
        # копируя в /mnt напрямую, без chroot.
        # AGENTS.md установленной системы — инструкция для агента в
        # целевой: логика двухфазной установки, логи, самопроверка
        # (идея 2026-09-26, реализация 2026-10-14). Системная копия —
        # источник; вторая — рядом с логами в ~/install-log первого
        # пользователя (uid 1000+ определяется динамически)
        deliver(FILES / "AGENTS-system.md", "/usr/local/share/wdistr/AGENTS.md"),
        "H=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $6; exit}') && "
        "U=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}') && "
        "[ -n \"$H\" ] && mkdir -p \"$H/install-log\" && "
        "cp /usr/local/share/wdistr/AGENTS.md \"$H/install-log/AGENTS.md\" && "
        "chown \"$U\" \"$H/install-log/AGENTS.md\"",
        # Системные дефолты dconf для всех пользователей: тема (её же
        # читают libadwaita-приложения — GTK4, Аутентификатор; GTK3
        # берут из /etc/gtk-3.0/settings.ini), цветовая схема для
        # портала xapp (Electron) и поведение рабочего стола (заставка,
        # монитор, кнопка питания — решение 2026-10-15). dconf update
        # собирает базу /etc/dconf/db/local из доставленных фрагментов
        deliver(FILES / "dconf-profile-user", "/etc/dconf/profile/user"),
        deliver(FILES / "dconf-local-theme", "/etc/dconf/db/local.d/00-wdistr-theme"),
        deliver(FILES / "dconf-local-desktop", "/etc/dconf/db/local.d/10-wdistr-desktop"),
        "dconf update",
        # Ассоциация папок: Nemo, а не VSCodium. codium.desktop держит
        # inode/directory и в mimeinfo.cache стоит первым по алфавиту —
        # без системного mimeapps.list диск открывался в редакторе
        # (опыт 2026-10-15). /etc/xdg/mimeapps.list приоритетнее
        # mimeinfo.cache; выбор пользователя в ~/.config его перекрывает
        deliver(FILES / "xdg-mimeapps.list", "/etc/xdg/mimeapps.list"),
        # Тёмная тема для Mozilla-приложений (Firefox, Thunderbird): у них
        # своя система тем, GTK/dconf они не читают — «системная» тема
        # следует за pref'ом ui.systemUsesDarkTheme. Дефолтный pref в
        # defaults/pref/, перекрывается about:config; pacman не трогает
        # при обновлениях (файл не в манифесте пакета)
        deliver(FILES / "mozilla-dark-theme.js",
                "/usr/lib/firefox/defaults/pref/wdistr-dark-theme.js"),
        deliver(FILES / "mozilla-dark-theme.js",
                "/usr/lib/thunderbird/defaults/pref/wdistr-dark-theme.js"),
        # fish — оболочка по умолчанию: root и первый обычный пользователь
        # (uid 1000+ определяется динамически — имя из setup не захардкожено)
        "usermod -s /usr/bin/fish root && "
        "getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}' | "
        "xargs -r -I{} usermod -s /usr/bin/fish {} && "
        "sed -i 's|^SHELL=.*|SHELL=/usr/bin/fish|' /etc/default/useradd",
        # PATH пользователя: ~/bin и ~/.local/bin — sh (login) и fish
        # раздельно: fish /etc/profile не читает (решение 2026-10-08)
        deliver(FILES / "profile-path.sh", "/etc/profile.d/wdistr-path.sh"),
        deliver(FILES / "fish-path.fish", "/etc/fish/conf.d/wdistr-path.fish"),
        # ФИКС композитора: пакет picom ставит свой автозапуск и при каждом
        # входе отбирал Composite у xfwm4 (handbook: «Проблема - picom...»)
        "rm -f /etc/xdg/autostart/picom.desktop",
        # Лечение первого входа в сессию (rate-swap) УБРАНО 2026-10-08:
        # глюк VirtualBox отрисовки курсора лечится протяжкой окна —
        # особенность зафиксирована в README и handbook («Проблема - Нет
        # курсора в XFCE»), автозапуск fix-session-gfx больше не ставим
        # SSH-ключ агента в authorized_keys больше НЕ доставляется
        # (решение 2026-10-12): вход агента в тестовую систему — sshpass
        # с паролем из setup; встроенный ключ был лишней скрытой связью
        # и лишним base64 в конфиге
        # keyd: конфиг раскладок и скрипт переключения (исходники в install/files/)
        deliver(FILES / "keyd.conf", "/etc/keyd/default.conf"),
        deliver(FILES / "toggle-layout.sh", "/usr/local/bin/keyd-toggle-layout", "755"),
        # Serial-доступ к платам Arduino для залогиненного пользователя
        # (uaccess вместо группы uucp; рецептура Arch wiki). arduino-ide-bin
        # udev-правил не ставит — без них загрузка скетча падает по
        # правам на /dev/ttyACM*/ttyUSB* (разведка 2026-10-14)
        deliver(FILES / "serial-uaccess.rules", "/etc/udev/rules.d/01-wdistr-serial.rules"),
        # системный дефолт GTK3: тёмная тема и Papirus для всех, включая
        # root (решение 2026-09-30; см. чек-лист «Комфортный рабочий стол»)
        deliver(FILES / "gtk3-settings.ini", "/etc/gtk-3.0/settings.ini"),
        # Курсоры McMojave, тема дистрибутива и карты раскладок keyd с
        # 2026-10-12 доставляются копированием из живой среды (шаг setup
        # после archinstall) — раньше шли gzip+base64 в JSON, для 3.4 МБ
        # курсоров это было непропорционально. Мелкие конфиги ниже
        # остаются base64.
        deliver(FILES / "cursor-default-index.theme", "/usr/share/icons/default/index.theme"),
        # xfce-xsettings.xml — глобальный дефолт темы XFCE. Cinnamon его
        # не читает, файл держим на случай установки xfce4 пользователем
        # (тема уже докинута; тогда же нужны xfce4 и xfce4-pulseaudio-plugin);
        # в карточке «Базовый набор программ» этот хвост не описываем
        deliver(
            FILES / "xfce-xsettings.xml",
            "/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml",
        ),
        # автоинициализация первого запуска: скрипт и systemd-юнит
        deliver(FILES / "first-boot.sh", "/usr/local/bin/wdistr-first-boot", "755"),
        deliver(FILES / "first-boot.service", "/etc/systemd/system/wdistr-first-boot.service"),
        # включение юнита ТОЛЬКО после его доставки (services[] выполняется раньше)
        "systemctl enable wdistr-first-boot.service",
        # повтор после падения: пока маркер first-boot-done не стоит,
        # таймер будит упавший юнит через час (сеть/зеркала при первом
        # запуске могут быть не готовы — опыт 2026-10-12). После успеха
        # условие таймера гасит его самого
        deliver(FILES / "first-boot-retry.timer", "/etc/systemd/system/wdistr-first-boot-retry.timer"),
        "systemctl enable wdistr-first-boot-retry.timer",
        # автообновление AUR: скрипт + юнит + еженедельный таймер
        # (обновляется только AUR через yay -Sua — система «на самотек»)
        deliver(FILES / "aur-update.sh", "/usr/local/bin/wdistr-aur-update", "755"),
        deliver(FILES / "aur-update.service", "/etc/systemd/system/wdistr-aur-update.service"),
        deliver(FILES / "aur-update.timer", "/etc/systemd/system/wdistr-aur-update.timer"),
        "systemctl enable wdistr-aur-update.timer",
        # автообновление СИСТЕМЫ и FLATPAK: тем же принципом, отдельными
        # таймерами — системой, AUR и flatpak управляют независимо
        deliver(FILES / "sys-update.sh", "/usr/local/bin/wdistr-sys-update", "755"),
        deliver(FILES / "sys-update.service", "/etc/systemd/system/wdistr-sys-update.service"),
        deliver(FILES / "sys-update.timer", "/etc/systemd/system/wdistr-sys-update.timer"),
        "systemctl enable wdistr-sys-update.timer",
        deliver(FILES / "flatpak-update.sh", "/usr/local/bin/wdistr-flatpak-update", "755"),
        deliver(FILES / "flatpak-update.service", "/etc/systemd/system/wdistr-flatpak-update.service"),
        deliver(FILES / "flatpak-update.timer", "/etc/systemd/system/wdistr-flatpak-update.timer"),
        "systemctl enable wdistr-flatpak-update.timer",
        # Повтор после сбоя: если обновление упало (обычно — сеть),
        # OnFailure в сервисе активирует шаблон, он спит 4 часа и
        # запускает упавшее обновление заново — не ждём недельного окна
        # (решение 2026-10-16). enable не нужен: шаблон стартует
        # инстансом по OnFailure, а не по таймеру
        deliver(FILES / "update-retry@.service", "/etc/systemd/system/wdistr-update-retry@.service"),
        # Проверка расписания Timeshift тем же замком (решение 2026-10-11):
        # ежечасный --check идёт в общей flock-очереди с автообновлениями,
        # снапшот не попадает в середину распаковки. cronie остаётся
        # выключенным — его cron-запуск обошёл бы блокировку; файл
        # /etc/cron.d/timeshift-hourly не трогаем (Timeshift пересоздаёт
        # его при сохранении настроек, он инертен)
        deliver(FILES / "timeshift-check.sh", "/usr/local/bin/wdistr-timeshift-check", "755"),
        deliver(FILES / "timeshift-check.service", "/etc/systemd/system/wdistr-timeshift-check.service"),
        deliver(FILES / "timeshift-check.timer", "/etc/systemd/system/wdistr-timeshift-check.timer"),
        "systemctl enable wdistr-timeshift-check.timer",
        # syncthing: ПОЛЬЗОВАТЕЛЬСКИЙ сервис включаем заранее — при первом
        # входе в десктоп user-менеджер поднимет синхронизацию без ручных
        # действий. systemctl --user из chroot недоступен (user-шины ещё
        # нет), поэтому пишем симлинк вручную — ровно то, что делает
        # enable: цель user-юнитов по умолчанию default.target.
        # chown — на весь .config: mkdir -p создаёт его от root, и без
        # полного chown dconf/Cinnamon падают на своей папке
        # (случай 2026-10-09: сломанный первый вход в Cinnamon)
        "U=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}') && "
        "test -n \"$U\" && "
        "mkdir -p /home/$U/.config/systemd/user/default.target.wants && "
        "ln -sf /usr/lib/systemd/user/syncthing.service "
        "/home/$U/.config/systemd/user/default.target.wants/syncthing.service && "
        "chown -R $U:$U /home/$U/.config",
        # docker: пользователь в группе docker — доступ к демону без sudo.
        # Поле groups в archinstall-creds.json группа НЕ назначает (проверено
        # установкой 2026-10-09: в /etc/group состав пуст) — назначаем сами,
        # как и shell у пользователя
        "U=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}') && "
        "test -n \"$U\" && "
        "usermod -aG docker \"$U\"",
        # Cinnamon при первом входе перебивает системный dconf-дефолт
        # (gtk-theme, шрифты) — одноразовый скрипт через системный
        # autostart ставит наши значения; маркер в ~/.config/wdistr не
        # даёт лезть в ручные настройки пользователя (решение 2026-10-09)
        deliver(FILES / "cinnamon-defaults.sh", "/usr/local/bin/wdistr-cinnamon-defaults", "755"),
        deliver(FILES / "wdistr-cinnamon-defaults.desktop", "/etc/xdg/autostart/wdistr-cinnamon-defaults.desktop"),
        # Сетевые правила пользователя (enp6s0, шлюз 192.168.0.1 —
        # железо хоста разработки): юниты системные, включение после
        # доставки; на машине с другим интерфейсом юнит упадёт по
        # таймауту ожидания сети — безвредно, включается только здесь.
        # Dispatcher-скрипт NetworkManager перезапускает ip-routing при
        # событиях сети (моргание кабеля, up/down amn0 у Amnezia):
        # маршруты через интерфейс ядро сбрасывает сам, сервис ставит
        # их заново. Без +x NM скрипт в dispatcher.d не запускает.
        deliver(FILES / "port-routing.service", "/etc/systemd/system/port-routing.service"),
        deliver(FILES / "ip-routing.service", "/etc/systemd/system/ip-routing.service"),
        deliver(FILES / "90-ip-routing-restart", "/etc/NetworkManager/dispatcher.d/90-ip-routing-restart", "755"),
        "systemctl enable port-routing.service ip-routing.service",
        # opencode собственной сборки: скрипт и патчи — в ~/bin первого
        # пользователя (паттерн с хоста разработки). Сборка на первом
        # запуске отключена (решение 2026-10-13) — opencode приходит
        # бинарником из ISO, обновления вручную: opencode.fish <версия>.
        # Переменная U живёт только внутри одной команды: каждая строка
        # custom_commands исполняется отдельным shell
        "U=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}') && "
        "test -n \"$U\" && " + " && ".join(
            [
                deliver(FILES / "opencode/opencode.fish", "/home/$U/bin/opencode.fish", "755"),
                deliver(FILES / "opencode/opencode-1.patch", "/home/$U/bin/opencode-1.patch"),
                deliver(FILES / "opencode/opencode-2.patch", "/home/$U/bin/opencode-2.patch"),
                deliver(FILES / "opencode/opencode-3.patch", "/home/$U/bin/opencode-3.patch"),
                deliver(FILES / "opencode/opencode-4.patch", "/home/$U/bin/opencode-4.patch"),
                "chown -R $U:$U /home/$U/bin",
            ]
        ),
    ]

    # Свои desktop-файлы: всё из files/desktop/ доставляется в
    # /usr/share/applications (вариант А, решение 2026-10-09). Новый файл
    # просто кладётся в папку — правка скрипта не нужна. Имена несут
    # префикс wdistr-: файл не принадлежит ни одному пакету, и при
    # обновлении pacman не должен упираться в чужой файл с тем же именем.
    for desktop in sorted((FILES / "desktop").glob("*.desktop")):
        config["custom_commands"].append(
            deliver(desktop, f"/usr/share/applications/{desktop.name}")
        )

    # Иконки игр Steam (Steam - Иконка игры на панели Cinnamon.md):
    # .desktop-файл ссылается Icon=steam_app_<appid>, но без файла иконки
    # панель откатывается к иконке Steam. Кладём в hicolor-тему по
    # РЕАЛЬНОМУ размеру PNG — GTK ищет по <размер>x<размер>/apps/, а
    # размеры у иконок разные (256/128/32), под size=256 всё не
    # подравнять. Размер читаем из заголовка IHDR структурно, без
    # Pillow — зависимости скрипта должны оставаться только stdlib.
    def png_size(path):
        with open(path, "rb") as fh:
            head = fh.read(24)
        if head[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        return struct.unpack(">II", head[16:24])  # (ширина, высота) из IHDR

    for icon in sorted((FILES / "icons").glob("*.png")):
        size = png_size(icon)
        if size is None or size[0] != size[1]:
            # Не PNG или не квадрат — hicolor-каталог требует квадратный
            # размер; такое не поддаём, чтобы не класть битую иконку
            print(f"WARNING: иконка {icon.name} не квадратный PNG ({size}) — пропущена")
            continue
        px = size[0]
        config["custom_commands"].append(
            deliver(icon, f"/usr/share/icons/hicolor/{px}x{px}/apps/{icon.name}")
        )

    # Автозапуск: всё из files/autostart/ доставляется в
    # /etc/xdg/autostart/ (решение 2026-10-16). Нужно для программ,
    # чьи пакеты НЕ ставят свой autostart-файл (amneziavpn-bin, copyq);
    # sticky автозапуск ставит сам пакет — своего файла не нужно.
    # emote: пакет тоже ставит свой файл, но автозапуск отключён хуком
    # wdistr-emote.hook (Hidden=true, решение 2026-10-17).
    # Паттерн тот же, что у desktop/.
    for desktop in sorted((FILES / "autostart").glob("*.desktop")):
        config["custom_commands"].append(
            deliver(desktop, f"/etc/xdg/autostart/{desktop.name}")
        )

    CONFIG.write_text(
        json.dumps(config, indent=4, sort_keys=True, ensure_ascii=False) + "\n"
    )
    shutil.copyfile(CONFIG, PROFILE_COPY)
    # Хук зеркал в профиль ISO (в airootfs до сборки — чтобы в живой среде
    # был хук, восстанавливающий список при обновлении pacman-mirrorlist)
    shutil.copyfile(MIRROR_HOOK, PROFILE_MIRROR_HOOK)
    # Хук gai.conf в профиль: срабатывает при установке glibc во время
    # сборки — строка приоритета IPv4 попадает в живую среду
    shutil.copyfile(GAI_HOOK, PROFILE_GAI_HOOK)
    # Хук ghostty в профиль: при сборке пакет ghostty ставится в живую
    # среду — хук правит его .desktop сразу (в цель .desktop правится
    # немедленным sed в custom_commands)
    shutil.copyfile(GHOSTTY_HOOK, PROFILE_GHOSTTY_HOOK)
    print(f"custom_commands: {len(config['custom_commands'])} команд(ы)")
    print(f"конфиг синхронизирован с профилем: {PROFILE_COPY}")
    print(f"mirrorlist из {MIRRORS.name} ({len(urls)} зеркал): {PROFILE_MIRRORLIST}")


if __name__ == "__main__":
    main()
