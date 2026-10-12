#!/usr/bin/env bash
# Создаёт тестовую VM wdistr-test для проверки СОБРАННОГО нашего ISO.
# Вход: свежий iso/out/wdistr-*.iso (берётся последний по времени).
# Выход: зарегистрированная VM с подключённым ISO и чистым диском.
# Пересоздание (штатная работа): VBoxManage unregistervm wdistr-test --delete
set -euo pipefail

VM_NAME="wdistr-test"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ISO_FILE="$(ls -t "$REPO_DIR"/iso/out/wdistr-*.iso | head -1)"
DISK_FILE="$SCRIPT_DIR/$VM_NAME.vdi"

# Ресурсы — под рабочую машину (16 ядер, ~123 ГБ RAM).
# Память 16 ГБ: первому запуску (AUR-сборки) нужно ~6.8 ГБ пиком,
# с 8 ГБ OOM killer убивает first-boot (случай 2026-10-09, см.
# Cards/Сборка ISO archiso)
MEMORY_MB=16384
CPUS=4
# Размер диска — первый аргумент в МиБ (по умолчанию 64 ГиБ, под который
# в исходнике конфига archinstall записаны разделы). Другой размер —
# способ проверить пересчёт корневого раздела в скрипте setup:
#     bash vm/create-test-vm.sh 51200   # диск 50 ГиБ
DISK_MB="${1:-65536}"

if [[ ! -f "$ISO_FILE" ]]; then
    echo "ОШИБКА: собранный ISO не найден в $REPO_DIR/iso/out/" >&2
    exit 1
fi

if VBoxManage showvminfo "$VM_NAME" >/dev/null 2>&1; then
    echo "VM '$VM_NAME' уже существует. Для пересоздания:"
    echo "  VBoxManage unregistervm $VM_NAME --delete"
    exit 1
fi

VBoxManage createvm --name "$VM_NAME" --ostype ArchLinux_64 --register
# Проброс ssh (2223->22) постоянный, живёт в файле .vbox: без него после
# каждого пересоздания SSH в тестовую не работал (случай 2026-09-27)
VBoxManage modifyvm "$VM_NAME" \
    --memory "$MEMORY_MB" --cpus "$CPUS" \
    --graphicscontroller vmsvga --vram 128 \
    --nic1 nat --audio-driver none \
    --boot1 dvd --boot2 disk \
    --natpf1 "ssh2,tcp,,2223,,22"
VBoxManage createmedium disk --filename "$DISK_FILE" --size "$DISK_MB" --format VDI
VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 \
    --type hdd --medium "$DISK_FILE"
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 1 --device 0 \
    --type dvddrive --medium "$ISO_FILE"

echo "VM '$VM_NAME' создана с ISO: $(basename "$ISO_FILE")"
echo "Запуск: VBoxManage startvm $VM_NAME"
