#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="penguin"
iso_label="PENGUIN_$(date +%Y%m)"
iso_publisher="Penguin <https://penguin.fyi>"
iso_application="Penguin Install & Rescue"
iso_version="$(date +%Y.%m.%d)"
install_dir="penguin"
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito' 'uefi-x64.systemd-boot.esp' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
