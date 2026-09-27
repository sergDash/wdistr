#!/usr/bin/env python3
"""Пересобирает custom_commands в install/archinstall-config.json.

Файловые настройки живут в install/files/ как исходники; здесь они
кодируются в base64. Так archinstall пишет каждую команду в скрипт
и выполняет его внутри целевой системы, поэтому кавычки и знаки $
в содержимом файлов не интерпретируются по пути.

Правило: после любой правки install/files/* запустить:
    python3 install/regen-custom-commands.py
и скопировать конфиг в профиль:
    cp install/archinstall-config.json iso/airootfs/root/wdistr/
(этот шаг делает скрипт автоматически — проверить вывод)."""

import base64
import json
import pathlib
import shutil

INSTALL = pathlib.Path(__file__).resolve().parent
CONFIG = INSTALL / "archinstall-config.json"
FILES = INSTALL / "files"
PROFILE_COPY = INSTALL.parent / "iso/airootfs/root/wdistr/archinstall-config.json"


def deliver(src: pathlib.Path, dest: str, mode: str | None = None) -> str:
    """Команда доставки файла src в dest целевой системы."""
    data = base64.b64encode(src.read_bytes()).decode()
    cmd = f"echo '{data}' | base64 -d > {dest}"
    if mode:
        cmd += f" && chmod {mode} {dest}"
    return cmd


def main() -> None:
    config = json.loads(CONFIG.read_text())

    config["custom_commands"] = [
        # multilib: конфиг archinstall включить его сам не умеет
        "sed -i '/#\\[multilib\\]/,/^#Include/ s/^#//' /etc/pacman.conf",
        # fish — оболочка по умолчанию: root, user и будущие пользователи
        "usermod -s /usr/bin/fish root && usermod -s /usr/bin/fish user && "
        "sed -i 's|^SHELL=.*|SHELL=/usr/bin/fish|' /etc/default/useradd",
        # курсор при входе в XFCE (handbook: «Проблема - Нет курсора в XFCE»)
        "mkdir -p /etc/xdg/xfce4/autostart && printf "
        "'[Desktop Entry]\\nType=Application\\nName=Fix cursor\\n"
        "Exec=xsetroot -cursor_name left_ptr\\nOnlyShowIn=XFCE;\\n' "
        "> /etc/xdg/xfce4/autostart/fix-cursor.desktop",
        # keyd: конфиг раскладок и скрипт переключения (исходники в install/files/)
        deliver(FILES / "keyd.conf", "/etc/keyd/default.conf"),
        deliver(FILES / "toggle-layout.sh", "/usr/local/bin/keyd-toggle-layout", "755"),
        # автоинициализация первого запуска: скрипт и systemd-юнит
        deliver(FILES / "first-boot.sh", "/usr/local/bin/wdistr-first-boot", "755"),
        deliver(FILES / "first-boot.service", "/etc/systemd/system/wdistr-first-boot.service"),
        # включение юнита ТОЛЬКО после его доставки (services[] выполняется раньше)
        "systemctl enable wdistr-first-boot.service",
    ]

    CONFIG.write_text(
        json.dumps(config, indent=4, sort_keys=True, ensure_ascii=False) + "\n"
    )
    shutil.copyfile(CONFIG, PROFILE_COPY)
    print(f"custom_commands: {len(config['custom_commands'])} команд(ы)")
    print(f"конфиг синхронизирован с профилем: {PROFILE_COPY}")


if __name__ == "__main__":
    main()
