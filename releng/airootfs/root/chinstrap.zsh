#!/usr/bin/env zsh

# chinstrap.zsh

# This is the Penguin install script. It is a very simple script -- meaning,
# it doesn't do anything for you. Setting up the installation environment
# (loadkeys, connecting network, etc.) is the users' responsibility. This is
# only meant to be a framework for the steps that should be taken during a
# normal Arch install. It is based directly on the Arch Linux Installation
# Guide, and should read pretty much in the same order. It is intended for you
# to read and edit this script to your liking. Not doing so may result in loss
# of data. Use of this script is AT YOUR OWN RISK!
#
# The installation consists of two stages:
# * stage1 - Prepare system and install packages (everything before chroot)
# * stage2 - Configure new system (everything inside of chroot)
#
# You can edit the options or stages in the areas between the banners.
#
# The default configuration:
# BIOS\MBR, 1 ext4 partition mounted to /, no swap
# full desktop, stock kernel

exit 1  # delete this line to confirm you have read this file

###############################################################################
##  COMMON VARIABLES ARE PROVIDED FOR CONVENIENCE ONLY, THEY ARE OPTIONAL    ##
###############################################################################

# settings for new systems
newuser="tux"
hostname=$(uname -n)
keymap="us"
vcfont="default8x16"
locale="en_US"
timezone="America/Chicago"

# install full desktop
packages=(
  penguin-base
  penguin-desktop
  penguin-defaults
)

# kernel
packages+=(linux)
#packages+=(linux-lts)
#packages+=(linux-zen)
#packages+=(linux-hardened)

# video drivers
packages+=(xorg-drivers)
#packages+=(nvidia)
#packages+=(vulkan-radeon)

# virtualbox guest
#packages+=(virtualbox-guest-utils)

# WILL USE ENTIRE DISK
rootdev=/dev/sda

###############################################################################
##  ^^^^^^^^^^^^^^^^^^^^^^ EDIT ABOVE THIS LINE ^^^^^^^^^^^^^^^^^^^^^^^^^^^  ##
###############################################################################

## INTERNAL VARIABLES (do not edit)
script=$0

# mount point for chroot
chroot=/mnt

# custom package list, overwrites $packages
custom=${0:A:h}/packages.txt

# for color output
m='\033[1;37m'  # msg, yellow
i='\033[1;33m'  # info, white
e='\033[1;31m'  # err, red
n='\033[0m'     # reset


## STAGE1
function stage1 {

  echo "${m}${script:t} - $(date)${n}"

  echo "${m}Testing network connection...${n}"
  if ping -4 -c 1 -w 5 penguin.fyi &>/dev/null
  then
    echo "${m}Updating system clock...${n}"
    timedatectl set-ntp true
  else
    echo "${e}ERROR: Network check failed!${n}"
    exit 1
  fi

  echo "${m}This is your ${e}LAST CHANCE TO STOP${m} the installation!${n}"
  echo "${i}Press Ctrl+c to quit or any other key to continue${n}"
  read -k1 -s || exit 1

###############################################################################
##  STAGE 1, PARTITION AND FORMAT TARGET DISK, INSTALL SOFTWARE PACKAGES     ##
###############################################################################

  ## PARTITION DISK (requred**)
  echo "${m}Preparing disk...${n}"

  # mbr, all for /
  parted --script $rootdev \
    mklabel msdos \
    mkpart primary 1MiB 100% \
    set 1 boot on
  local root="${rootdev}1"

  ## UEFI\GPT EXAMPLE
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


  ## FORMAT PARTITIONS (required**)
  echo "${m}Formatting partitions...${n}"

  # mbr
  mkfs.ext4 $root

  ## efi
  #mkfs.vfat $boot
  #mkfs.f2fs -f $root
  #mkswap $swap


  ## MOUNT PARTITIONS (required)
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

  sync  # required

  unset boot swap root


  ## PACMAN OPTIONS (optional)
  echo "${m}Tweak pacman config...${n}"
  sed -i "/Color/s/^#//
    /TotalDownload/s/^#//
    /CheckSpace/s/^#//" \
    /etc/pacman.conf


  ## GET FAST PACMAN MIRRORS (optional)
  echo "${m}Update pacman mirrors...${n}"
  reflector \
    --protocol https \
    --country US \
    --age 12 \
    --sort rate \
    --save /etc/pacman.d/mirrorlist
  pacman -Sy


  ## PACSTRAP PACKAGES (required)
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
  packages+=(zsh)   # make sure we have zsh in chroot
  pacstrap $chroot ${packages[*]} --needed

  unset line packages


  ## GENERATE FSTAB (required)
  echo "${m}Generating fstab...${n}"
  genfstab -U -p $chroot > $chroot/etc/fstab

###############################################################################
##  ^^^^^^^^^^^^^^^^^^^^^^ EDIT ABOVE THIS LINE ^^^^^^^^^^^^^^^^^^^^^^^^^^^  ##
###############################################################################

  echo "${m}Starting chroot environment...${n}"
  local script2=${script:t}

  # copy script to chroot env
  cp $script $chroot/$script2
  chmod 755 $chroot/$script2

  arch-chroot $chroot /$script2 --chroot
  rm $chroot/$script2

  echo "${m}Unmounting...${n}"
  umount -R $chroot
  swapoff -a

  unset script2

  echo "${i}Installation is complete =)${n}"
  finish_prompt
}


## STAGE2
function stage2 { 

###############################################################################
##  STAGE 2, POST-INSTALL CONFIGURATION, RUN IN CHROOT ENVIRONMENT           ##
###############################################################################

  ## SET TIMEZONE (required)
  echo "${m}Setting timezone to '${n}$timezone${m}'${n}"
  ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
  hwclock --systohc --utc


  ## SET TIME SYNC (optional)
  echo "${m}Enabling time synchronization...${n}"
  systemctl enable systemd-timesyncd


  ## SET LOCALE (required)
  echo "${m}Setting locale to '${n}$locale${m}'${n}"
  echo "LANG=$locale.UTF-8" > /etc/locale.conf
  sed -i "/$locale.UTF-8/s/^#//g" /etc/locale.gen
  locale-gen


  ## SET KEYMAP (required)
  echo "${m}Setting keymap to '${n}$keymap${m}'${n}"
  echo "KEYMAP=$keymap" > /etc/vconsole.conf


  # SET CONSOLE FONT (optional)
  echo "${m}Setting font to '${n}$vcfont${m}'${n}"
  echo "FONT=$vcfont" >> /etc/vconsole.conf


  # SET HOSTNAME (required)
  echo "${m}Setting hostname to '${n}$hostname${m}'${n}"
  echo $hostname > /etc/hostname


  # WRITE HOSTS FILE (optional)
  echo "${m}Writing '/etc/hosts'...${n}"
  echo "127.0.0.1  localhost" > /etc/hosts
  echo "::1        localhost" >> /etc/hosts
  echo "127.0.1.1  $hostname.localdomain  $hostname" >> /etc/hosts


  ## ENABLE SERVICES (optional)
  # all services required by penguin-desktop automatically started

  #echo "${m}Enabling SSH service...${n}"
  #systemctl enable sshd

  #echo "${m}VirtualBox guest service...${n}"
  #systemctl enable vboxservice


  ## INSTALL BOOTLOADER (required)
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


  ## ADD USERS (optional)
  if [[ -n $newuser ]]
  then
    echo "${m}Adding user '${i}$newuser${m}'${n}"
    # wheel group privileged
    useradd -U -G wheel -m $newuser
    echo "${m}Set password for '${i}$newuser${m}'${n}"
    passwd $newuser
    grpck
  fi

###############################################################################
##  ^^^^^^^^^^^^^^^^^^^^^^ EDIT ABOVE THIS LINE ^^^^^^^^^^^^^^^^^^^^^^^^^^^  ##
###############################################################################

  echo "${m}Set password for '${i}root${m}'${n}"
  passwd || { echo "${e}YOU MUST SET A ROOT PASSWORD!${n}"; passwd }

  return
}


function finish_prompt() {
  if read -q REPLY\?"Would you like to reboot now? (y/n)\n"
  then
    reboot
  else
    echo "${m}Continuing with live system, reboot when ready!${n}"
  fi
}


function usage() {
  echo "Usage: ${script:t} [--arg]"
  echo
  echo "Arguments:"
  echo "  --write               write defaults to packages.txt for editing"
  echo "  -h  | --help          this help message"
  echo
  exit 0
}


function write_packages() {
  [[ -f $custom ]] && rm $custom
  for pkg in $packages[@]
  do
    echo $pkg >> $custom
  done
  exit 0
}


# call stages
case $1 in
  -h | --help)
    usage
  ;;
  --write)
    write_packages
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
