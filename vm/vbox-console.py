#!/usr/bin/env python3
"""Ввод команды в консоль виртуальной машины VirtualBox без SSH.

Переводит строку ASCII (раскладка US) в сканкоды клавиатуры (set 1) и
отправляет их гостю через `VBoxManage controlvm ... keyboardputscancode`.
Нужен, когда SSH в гостя недоступен (например, живая среда нашего ISO —
у root пустой пароль, а sshd пустые пароли не пускает).

Использование:
    python3 vm/vbox-console.py <имя_vm> "<команда>" [noreset]

По умолчанию перед командой шлётся Ctrl+C (прервать выполняющуюся
команду и очистить строку ввода). Флаг `noreset` — вводить без Ctrl+C
(для ответов на запросы вроде подтверждений zsh).

После ввода результат снимается скриншотом:
    VBoxManage controlvm <имя_vm> screenshotpng /tmp/shot.png
и читается инструментом просмотра изображений.
"""
import subprocess
import sys

# set-1 сканкоды для US-раскладки (консоль гостя по умолчанию в ней)
MAKE = {
    "1": 0x02, "2": 0x03, "3": 0x04, "4": 0x05, "5": 0x06,
    "6": 0x07, "7": 0x08, "8": 0x09, "9": 0x0A, "0": 0x0B,
    "-": 0x0C, "=": 0x0D, "\t": 0x0F, "q": 0x10, "w": 0x11,
    "e": 0x12, "r": 0x13, "t": 0x14, "y": 0x15, "u": 0x16,
    "i": 0x17, "o": 0x18, "p": 0x19, "[": 0x1A, "]": 0x1B,
    "a": 0x1E, "s": 0x1F, "d": 0x20, "f": 0x21, "g": 0x22,
    "h": 0x23, "j": 0x24, "k": 0x25, "l": 0x26, ";": 0x27,
    "'": 0x28, "`": 0x29, "\\": 0x2B, "z": 0x2C, "x": 0x2D,
    "c": 0x2E, "v": 0x2F, "b": 0x30, "n": 0x31, "m": 0x32,
    ",": 0x33, ".": 0x34, "/": 0x35, " ": 0x39,
}
SHIFTED = {  # символ -> (сканкод базовой клавиши, нужен ли Shift)
    "!": (0x02, True), "@": (0x03, True), "#": (0x04, True),
    "$": (0x05, True), "%": (0x06, True), "^": (0x07, True),
    "&": (0x08, True), "*": (0x09, True), "(": (0x0A, True),
    ")": (0x0B, True), "_": (0x0C, True), "+": (0x0D, True),
    ":": (0x27, True), '"': (0x28, True), "~": (0x29, True),
    "<": (0x33, True), ">": (0x34, True), "?": (0x35, True),
    "|": (0x2B, True), "{": (0x1A, True), "}": (0x1B, True),
}
ENTER, LSHIFT = 0x1C, 0x2A
CTRL, C_KEY = 0x1D, 0x2E


def tap(code: int, extra: int | None = None) -> list[int]:
    """Нажатие клавиши: модификатор зажимается до нажатия и отпускается после."""
    seq = []
    if extra is not None:
        seq.append(extra)
    seq += [code, code | 0x80]
    if extra is not None:
        seq.append(extra | 0x80)
    return seq


def send(vm: str, cmd: str, reset: bool) -> None:
    # Ctrl+C — прервать выполняющуюся команду и очистить строку ввода
    seq = tap(C_KEY, CTRL) if reset else []
    for ch in cmd:
        if ch in MAKE:
            seq += tap(MAKE[ch])
        elif ch in SHIFTED:
            base, need_shift = SHIFTED[ch]
            seq += tap(base, LSHIFT if need_shift else None)
        elif ch.lower() in MAKE:  # заглавные буквы — через Shift
            seq += tap(MAKE[ch.lower()], LSHIFT)
        else:
            raise SystemExit(f"нет трансляции для символа {ch!r}")
    seq += tap(ENTER)
    # по 20 байт на вызов: make/break каждой клавиши подряд
    for i in range(0, len(seq), 20):
        chunk = seq[i:i + 20]
        subprocess.run(
            ["VBoxManage", "controlvm", vm, "keyboardputscancode"]
            + [f"{b:02x}" for b in chunk],
            check=True, capture_output=True,
        )


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    vm = sys.argv[1]
    cmd = sys.argv[2]
    reset = len(sys.argv) < 4 or sys.argv[3] != "noreset"
    send(vm, cmd, reset=reset)
    print(f"[{vm}] введено: {cmd}")


if __name__ == "__main__":
    main()
