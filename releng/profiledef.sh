#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="penguin"
iso_label="PENG_$(date +%Y%m)"
iso_publisher="Penguin.FYI <https://penguin.fyi>"
iso_application="Penguin Live/Rescue CD"
iso_version="$(date +%Y.%m.%d)"
install_dir="penguin"
gpg_key="8A9EB74DE80CEDAABC612A123C2152E6699D8061"
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito' 'uefi-x64.systemd-boot.esp' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/root/chinstrap.zsh"]="0:0:755"
)
