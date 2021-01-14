#!/usr/bin/env zsh

# install.zsh

###############################################################################

# settings for new systems
newuser="spider"
hostname=$(uname -n)
keymap="us"
vcfont="default8x16"
locale="en_US"
timezone="America/Chicago"

# install full desktop
packages=(
  linux-zen
  penguin-base
  penguin-desktop
  penguin-defaults
  xorg-drivers
  base-devel
)

# custom package list
# overwrites $packages, make sure you have what you need
custom=${0:A:h}/packages.txt

# WILL USE ENTIRE DISK
rootdev=/dev/sda

# mount point for chroot
chroot=/mnt

###############################################################################

script=$0
echo "${m}${script:t} - $(date)${n}"

# stage1 begins installation
function stage1 {

  echo "${m}You are about to ${e}DESTROY ALL DATA${m} on '${i}$rootdev${m}'${n}"
  echo "${i}Press any to continue${n}"
  read -k1 -s || exit 1

  echo "${m}Beginning installation!${n}"

  echo "${m}Testing network connection...${n}"
  if ! ping -4 -c 1 -w 5 archlinux.org &>/dev/null
  then
    echo "${e}ERROR: Network check failed!${n}"
    exit 1
  fi

  echo "${m}Updating system clock...${n}"
  timedatectl set-ntp true

  echo "${m}Preparing disk...${n}"
  # mbr, all for /
  parted --script $rootdev \
    mklabel msdos \
    mkpart primary 1MiB 100% \
    set 1 boot on

  local root="${rootdev}1"

  ## efi, 260mb esp, 4gb swap, rest for /
  #parted --script $rootdev \
  #  mklabel gpt \
  #  mkpart primary 1MiB 260MiB \
  #  set 1 esp on \
  #  mkpart primary 260MiB 4356MiB \
  #  mkpart primary 4356MiB 100%

  #local boot="${rootdev}1"
  #local swap="${rootdev}2"
  #local root="${rootdev}3"

  echo "${m}Formatting partitions...${n}"
  # mbr
  mkfs.ext4 $root

  ## efi
  #mkfs.vfat $boot
  #mkfs.f2fs -f $root
  #mkswap $swap

  echo "${m}Mounting partitions...${n}"
  # mbr
  mkdir -p $chroot
  mount $root $chroot

  ## efi
  #mkdir -p $chroot
  #mount $root $chroot
  #mkdir -p $chroot/boot
  #mount $boot $chroot/boot
  #swapon $swap

  sync

  unset boot swap root

  echo "${m}Tweak pacman config...${n}"
  sed -i "/Color/s/^#//
    /TotalDownload/s/^#//
    /CheckSpace/s/^#//" \
    /etc/pacman.conf

  echo "${m}Update pacman mirrors...${n}"
  reflector \
    --protocol https \
    --country US \
    --age 12 \
    --sort rate \
    --save /etc/pacman.d/mirrorlist
  pacman -Sy

  echo "${m}Installing packages...${n}"
  if [[ -f $custom ]]
  then
    echo "${i}Found custom package list...${n}"
    unset packages

    local line
    while IFS= read -r line
    do
      packages+=($line)
    done < $custom
  fi
  packages=($packages zsh)
  pacstrap $chroot ${packages[*]} --needed

  unset line packages

  echo "${m}Generating fstab...${n}"
  genfstab -U -p $chroot > $chroot/etc/fstab


  echo "${m}Starting chroot environment...${n}"
  local stage2=${script:t}

  # copy script to chroot env
  cp $script $chroot/$stage2
  chmod 755 $chroot/$stage2

  arch-chroot $chroot /$stage2 --chroot
  rm $chroot/$stage2

  echo "${m}Unmounting...${n}"
  umount -R $chroot
  swapoff -a

  unset stage2

  echo "${i}Installation is complete =)${n}"
}

# stage2 is run in chroot env
function stage2 { 

  echo "${m}Setting timezone to '${n}$timezone${m}'${n}"
  ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
  hwclock --systohc --utc

  echo "${m}Enabling time synchronization...${n}"
  systemctl enable systemd-timesyncd

  echo "${m}Setting locale to '${n}$locale${m}'${n}"
  echo "LANG=$locale.UTF-8" > /etc/locale.conf
  sed -i "/$locale.UTF-8/s/^#//g" /etc/locale.gen
  locale-gen

  echo "${m}Setting keymap to '${n}$keymap${m}'${n}"
  echo "KEYMAP=$keymap" > /etc/vconsole.conf

  echo "${m}Setting font to '${n}$vcfont${m}'${n}"
  echo "FONT=$vcfont" >> /etc/vconsole.conf

  echo "${m}Setting hostname to '${n}$hostname${m}'${n}"
  echo $hostname > /etc/hostname

  echo "${m}Writing '/etc/hosts'...${n}"
  echo "127.0.0.1  localhost" > /etc/hosts
  echo "::1        localhost" >> /etc/hosts
  echo "127.0.1.1  $hostname.localdomain  $hostname" >> /etc/hosts

#  echo "${m}Enabling DHCP service...${n}"
#  systemctl enable dhcpcd
#
#  echo "${m}Enabling SSH service...${n}"
#  systemctl enable sshd
#
#  echo "${m}Enabling display manager...${n}"
#  systemctl enable xdm
#
#  echo "${m}Configuring default window manager...${n}"
#  cat >/etc/skel/.xinitrc <<EOF
##!/bin/bash
#
#xrdb -merge .Xresources
#
#xsetroot -solid grey20
#
#exec i3
#EOF
#  chmod +x /etc/skel/.xinitrc
#  cat >/etc/skel/.Xresources <<EOF
#URxvt*background: black
#URxvt*foreground: gray
#URxvt*font: xft:DejaVu Sans Mono:size=9
#EOF

  echo "${m}Configuring bootloader...${n}"
  # MBR
  grub-install \
    --target=i386-pc \
    $rootdev
  ## EFI
  #grub-install \
  #  --target=x86_64-efi \
  #  --efi-directory=/boot \
  #  --recheck \
  #  $rootdev
  grub-mkconfig -o /boot/grub/grub.cfg

  if [[ -n $newuser ]]
  then
    echo "${m}Adding user '${i}$newuser${m}'${n}"
    useradd -U -G wheel -m $newuser
    echo "${m}Set password for '${i}$newuser${m}'${n}"
    passwd $newuser
    #echo "$newuser ALL=(ALL:ALL) ALL" >> /etc/sudoers
    grpck
    cp $script /home/$newuser/$script
    chown $newuser:$newuser /home/$newuser/$script
  fi

  echo "${m}Set password for '${i}root${m}'${n}"
  passwd || { echo "${e}NO ROOT PASSWORD IS DANGEROUS!${n}"; passwd }

  return
}

# for color output
m='\033[1;37m'  # msg, yellow
i='\033[1;33m'  # info, white
e='\033[1;31m'  # err, red
n='\033[0m'     # reset

# call stages
case $1 in
  -h | --help)
    echo "Usage: ${script:t} [--arg]"
    echo
    echo "Arguments:"
    echo "  -wp | --write-pkglist     write defaults to packages.txt for editing"
    echo "  -h  | --help              this help message"
    echo
    exit 0
  ;;
  -wp | --write-pkgs)
    [[ -f $custom ]] && rm $custom
    for pkg in $packages[@]
    do
      echo $pkg >> $custom
    done
    exit 0
  ;;
  --chroot)
    stage2
  ;;
  *)
    stage1
  ;;
esac

exit 0

# vim: ft=zsh ts=2 sw=0 et:
