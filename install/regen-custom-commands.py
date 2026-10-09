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

INSTALL = pathlib.Path(__file__).resolve().parent
CONFIG = INSTALL / "archinstall-config.json"
FILES = INSTALL / "files"
PROFILE_COPY = INSTALL.parent / "iso/airootfs/root/wdistr/archinstall-config.json"

# Единый список зеркал дистрибутива (решение 2026-10-08): и живая среда,
# и устанавливаемая работают только с ним. Отсюда он раздаётся в профиль
# ISO (живая среда) и в custom_commands (целевая система).
MIRRORS = INSTALL.parent / "mirrors.txt"
MIRROR_HOOK = FILES / "wdistr-mirrors.hook"
PROFILE_MIRRORLIST = INSTALL.parent / "iso/airootfs/usr/local/share/wdistr/mirrorlist"
PROFILE_MIRROR_HOOK = INSTALL.parent / "iso/airootfs/etc/pacman.d/hooks/wdistr-mirrors.hook"


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


def deliver_pubkey() -> str:
    """Команда доставки публичного ключа агента в authorized_keys.

    Домашний каталог и владелец определяются по первому обычному
    пользователю (uid 1000–65534) — имя из setup не захардкожено."""
    pub = (pathlib.Path.home() / ".ssh" / "wdistr_build_vm.pub").read_text().strip()
    b64 = base64.b64encode(pub.encode()).decode()
    return (
        "U=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}') && "
        "test -n \"$U\" && "
        "mkdir -p /home/$U/.ssh && "
        f"echo '{b64}' | base64 -d > /home/$U/.ssh/authorized_keys && "
        "chmod 700 /home/$U/.ssh && chmod 600 /home/$U/.ssh/authorized_keys && "
        "chown -R $U:$U /home/$U/.ssh"
    )


def main() -> None:
    config = json.loads(CONFIG.read_text())

    # Зеркала: в mirrors.txt — просто URL построчно, этого списка
    # достаточно для archinstall (mirror_regions — массив голых URL), но
    # самому pacman нужен файл вида 'Server = <url>', а локальному
    # парсеру зеркал archinstall (--offline) — заголовок региона '## Russia':
    # без него сервера попадут в регион 'Local' и установка упадёт.
    # Генерируем mirrorlist и кладём в профиль ДО сборки custom_commands:
    # команды доставки кодируют содержимое файла, поэтому файл должен быть
    # готов заранее.
    urls = [line.strip() for line in MIRRORS.read_text().splitlines() if line.strip()]
    PROFILE_MIRRORLIST.parent.mkdir(parents=True, exist_ok=True)
    PROFILE_MIRRORLIST.write_text(
        "## Russia\n" + "".join(f"Server = {url}\n" for url in urls)
    )
    config["mirror_config"]["mirror_regions"] = {"Russia": urls}

    config["custom_commands"] = [
        # multilib: конфиг archinstall включить его сам не умеет
        "sed -i '/#\\[multilib\\]/,/^#Include/ s/^#//' /etc/pacman.conf",
        # Зеркала wdistr (mirrors.txt → mirrorlist): хук + источник, затем
        # прямая запись mirrorlist — archinstall пишет свой список до
        # pacstrap, а пакет pacman-mirrorlist при установке затирает его
        # стоковым; хук в дальнейшем восстанавливает список при обновлениях
        deliver(MIRROR_HOOK, "/etc/pacman.d/hooks/wdistr-mirrors.hook"),
        deliver(PROFILE_MIRRORLIST, "/usr/local/share/wdistr/mirrorlist"),
        deliver(PROFILE_MIRRORLIST, "/etc/pacman.d/mirrorlist"),
        # Тёмная тема для всех пользователей: система-дефолты dconf — их
        # читают libadwaita-приложения (GTK4, Аутентификатор), а обычные
        # GTK3 берут тему из /etc/gtk-3.0/settings.ini; dconf update
        # собирает базу /etc/dconf/db/local из доставленных фрагментов
        deliver(FILES / "dconf-profile-user", "/etc/dconf/profile/user"),
        deliver(FILES / "dconf-local-theme", "/etc/dconf/db/local.d/00-wdistr-theme"),
        "dconf update",
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
        # SSH-ключ агента в authorized_keys — доступ по ключу сразу после
        # каждой установки, без ручного копирования
        deliver_pubkey(),
        # keyd: конфиг раскладок и скрипт переключения (исходники в install/files/)
        deliver(FILES / "keyd.conf", "/etc/keyd/default.conf"),
        deliver(FILES / "toggle-layout.sh", "/usr/local/bin/keyd-toggle-layout", "755"),
        # системный дефолт GTK3: тёмная тема и Papirus для всех, включая
        # root (решение 2026-09-30; см. чек-лист «Комфортный рабочий стол»)
        deliver(FILES / "gtk3-settings.ini", "/etc/gtk-3.0/settings.ini"),
        # курсор McMojave: tar (3.2 МБ, gzip+base64) раскрывается в
        # /usr/share/icons/McMojave-cursors; затем два способа назначения —
        # системный default/index.theme (для не-GTK) и глобальный дефолт
        # сессии xfce (xfsettingsd главнее GTK) — решение 2026-10-08
        deliver(FILES / "mcMojave-cursors.tar", "/var/tmp/mcMojave-cursors.tar", compress=True),
        "tar -xf /var/tmp/mcMojave-cursors.tar -C /usr/share/icons "
        "&& rm -f /var/tmp/mcMojave-cursors.tar",
        deliver(FILES / "cursor-default-index.theme", "/usr/share/icons/default/index.theme"),
        deliver(
            FILES / "xfce-xsettings.xml",
            "/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml",
        ),
        # предсобранные консольные карты раскладок (ckbcomp, ~21 мс на смену)
        deliver(FILES / "keymaps/us.txt", "/usr/local/share/keyd/us.txt", compress=True),
        deliver(FILES / "keymaps/ru.txt", "/usr/local/share/keyd/ru.txt", compress=True),
        # автоинициализация первого запуска: скрипт и systemd-юнит
        deliver(FILES / "first-boot.sh", "/usr/local/bin/wdistr-first-boot", "755"),
        deliver(FILES / "first-boot.service", "/etc/systemd/system/wdistr-first-boot.service"),
        # включение юнита ТОЛЬКО после его доставки (services[] выполняется раньше)
        "systemctl enable wdistr-first-boot.service",
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
        # opencode собственной сборки: скрипт и патчи — в ~/bin первого
        # пользователя (паттерн с хоста разработки). Первая сборка и
        # обновления — запуск opencode.fish от пользователя (first-boot),
        # переменная U живёт только внутри одной команды: каждая строка
        # custom_commands исполняется отдельным shell
        "U=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}') && "
        "test -n \"$U\" && " + " && ".join(
            [
                deliver(FILES / "opencode/opencode.fish", "/home/$U/bin/opencode.fish", "755"),
                deliver(FILES / "opencode/opencode-1.patch", "/home/$U/bin/opencode-1.patch"),
                deliver(FILES / "opencode/opencode-2.patch", "/home/$U/bin/opencode-2.patch"),
                deliver(FILES / "opencode/opencode-3.patch", "/home/$U/bin/opencode-3.patch"),
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

    CONFIG.write_text(
        json.dumps(config, indent=4, sort_keys=True, ensure_ascii=False) + "\n"
    )
    shutil.copyfile(CONFIG, PROFILE_COPY)
    # Хук зеркал в профиль ISO (в airootfs до сборки — чтобы в живой среде
    # был хук, восстанавливающий список при обновлении pacman-mirrorlist)
    shutil.copyfile(MIRROR_HOOK, PROFILE_MIRROR_HOOK)
    print(f"custom_commands: {len(config['custom_commands'])} команд(ы)")
    print(f"конфиг синхронизирован с профилем: {PROFILE_COPY}")
    print(f"mirrorlist из {MIRRORS.name} ({len(urls)} зеркал): {PROFILE_MIRRORLIST}")


if __name__ == "__main__":
    main()
