#!/usr/bin/env bash
# Создаёт виртуальную машину-сборщик wdistr-build в VirtualBox.
# Вход: каталог vm/ рядом со скриптом; ISO Arch скачивается сюда же при отсутствии.
# Выход: зарегистрированная VM с подключённым ISO и пустым диском.
#         Дальше установка Arch — вручную в окне VM (archinstall).
set -euo pipefail

VM_NAME="wdistr-build"
ISO_VERSION="2026.09.01"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ISO_FILE="$SCRIPT_DIR/archlinux-$ISO_VERSION.iso"
ISO_URL="https://geo.mirror.pkgbuild.com/iso/$ISO_VERSION/archlinux-x86_64.iso"
DISK_FILE="$SCRIPT_DIR/$VM_NAME.vdi"

# Ресурсы сборочной машины: хост разработки имеет 16 ядер и ~100 ГБ RAM,
# но сборке archiso достаточно и такого запаса
MEMORY_MB=8192
CPUS=4
DISK_MB=65536

# ISO — входные данные для установки; в git не попадает (.gitignore)
if [[ ! -f "$ISO_FILE" ]]; then
    echo "Скачиваю ISO: $ISO_URL"
    curl -fL --progress-bar -o "$ISO_FILE.part" "$ISO_URL"
    mv "$ISO_FILE.part" "$ISO_FILE"
fi

# Повторный запуск не должен молча затирать существующую машину
if VBoxManage showvminfo "$VM_NAME" >/dev/null 2>&1; then
    echo "VM '$VM_NAME' уже существует. Для пересоздания:"
    echo "  VBoxManage unregistervm $VM_NAME --delete"
    exit 1
fi

VBoxManage createvm --name "$VM_NAME" --ostype ArchLinux_64 --register
VBoxManage modifyvm "$VM_NAME" \
    --memory "$MEMORY_MB" --cpus "$CPUS" \
    --graphicscontroller vmsvga --vram 128 \
    --nic1 nat --audio-driver none \
    --boot1 dvd --boot2 disk
VBoxManage createmedium disk --filename "$DISK_FILE" --size "$DISK_MB" --format VDI
VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 \
    --type hdd --medium "$DISK_FILE"
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 1 --device 0 \
    --type dvddrive --medium "$ISO_FILE"

echo "VM '$VM_NAME' создана. Запуск: VBoxManage startvm $VM_NAME"
