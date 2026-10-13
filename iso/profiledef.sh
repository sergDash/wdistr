#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="wdistr"
iso_label="WDISTR_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="wdistr"
iso_application="wdistr Live/Install DVD"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86,arm64' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/wdistr/go.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/usr/local/bin/setup"]="0:0:755"
  ["/usr/local/bin/disks"]="0:0:755"
  # archiso копирует airootfs с --no-preserve=mode: без этой записи файл
  # приходит в живую среду без +x (опыт 2026-10-12: opencode отдавал
  # «permission denied»). Версия в имени файла — при смене версии
  # обновлять наравне с симлинком opencode.
  ["/usr/local/bin/opencode-1.19.0+"]="0:0:755"
  ["/usr/local/bin/keyd-toggle-layout"]="0:0:755"
)
