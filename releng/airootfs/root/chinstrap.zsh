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

# install full developer desktop
packages=(
  penguin-base
  penguin-desktop
  penguin-dev-tools
)

# kernel
packages+=(linux)
#packages+=(linux-lts)
#packages+=(linux-zen)
#packages+=(linux-hardened)

# microcode
#packages+=(amd-ucode)
#packages+=(intel-ucode)

# video drivers
#packages+=(nvidia)
#packages+=(vulkan-radeon)
packages+=(xorg-drivers)

# laptop power management (enable service in stage2)
#packages+=(tlp)

# virtualbox guest (enable service in stage2)
#packages+=(virtualbox-guest-utils)

# WILL USE ENTIRE DISK
rootdev=/dev/sda

###############################################################################
##  ^^^^^^^^^^^^^^^^^^^^^^ EDIT ABOVE THIS LINE ^^^^^^^^^^^^^^^^^^^^^^^^^^^  ##
###############################################################################

## INTERNAL VARIABLES (do not edit)
script=$0

# custom package list, overwrites $packages
custom=${script:A:h}/packages.txt

# mount point for chroot
chroot=/mnt

# color output (msg,info,err,reset)
m='\033[1;35m'; i='\033[1;32m'; e='\033[1;31m'; n='\033[0m'

## STAGE1
function stage1 {

  echo "${m}${script:t} - $(date)${n}"

  echo "${m}Verifying boot mode...${n}"
  if test -d /sys/firmware/efi/efivars
  then
    echo "${i}UEFI detected!${n}"
  else
    echo "${i}BIOS detected!${n}"
  fi

  echo "${m}Testing network connection...${n}"
  if ping -4 -c 1 -w 5 penguin.fyi &>/dev/null
  then
    echo "${i}OK${n}"
    echo "${m}Updating system clock...${n}"
    if timedatectl set-ntp true
    then
      echo "${i}OK${n}"
    fi
  else
    echo "${e}ERROR: Network check failed!${n}"
    echo "${i}Aborting!${n}"
    exit 1
  fi

  echo "${m}Are you ready to begin?${n}"
  vared -cp "Confirm (y/n)? " ans
  [[ "$ans" =~ ^[Yy]$ ]] || exit 1

###############################################################################
##  STAGE 1, PARTITION AND FORMAT TARGET DISK, INSTALL SOFTWARE PACKAGES     ##
###############################################################################

  ## BIOS\MBR example
  ## PARTITION DISK (requred**)
  echo "${m}Preparing disk...${n}"

  # MSDOS partition table
  # 1 partition, ext4
  parted --script $rootdev \
    mklabel msdos \
    mkpart primary ext4 1MiB 100% \
    set 1 boot on
  local root="${rootdev}1"

  ## FORMAT PARTITIONS (required**)
  echo "${m}Formatting partitions...${n}"

  mkfs.ext4 $root

  ## MOUNT PARTITIONS (required)
  echo "${m}Mounting partitions...${n}"

  mkdir -p $chroot
  mount $root $chroot

#  ## UEFI\GPT example
#  ## PARTITION DISK (requred**)
#  echo "${m}Preparing disk...${n}"
#
#  # GPT partition table
#  # 3 partitions, 260mb fat32 ESP, 2gb swap, remaining ext4
#  parted --script $rootdev \
#    mklabel gpt \
#    mkpart primary fat32 1MiB 260MiB \
#    set 1 esp on \
#    mkpart primary 260MiB 2308MiB \
#    mkpart primary 2308MiB 100%
#  local boot="${rootdev}1"
#  local swap="${rootdev}2"
#  local root="${rootdev}3"
#
#  ## FORMAT PARTITIONS (required**)
#  echo "${m}Formatting partitions...${n}"
#
#  mkfs.vfat $boot
#  mkfs.ext4 $root
#  mkswap $swap
#
#  ## MOUNT PARTITIONS (required)
#  echo "${m}Mounting partitions...${n}"
#  
#  mkdir -p $chroot
#  mount $root $chroot
#  mkdir -p $chroot/boot
#  mount $boot $chroot/boot
#  swapon $swap

  # required after partition and format
  sync 

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

  # sync db after making changes to conf or mirrors
  pacman -Syy


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

###############################################################################
##  ^^^^^^^^^^^^^^^^^^^^^^ EDIT ABOVE THIS LINE ^^^^^^^^^^^^^^^^^^^^^^^^^^^  ##
###############################################################################

  # generate new fstab
  echo "${m}Generating fstab...${n}"
  genfstab -U -p $chroot > $chroot/etc/fstab

  echo "${m}Starting chroot environment...${n}"
  local script2=${script:t}

  # copy script to chroot env
  cp $script $chroot/$script2
  chmod 755 $chroot/$script2

  arch-chroot $chroot /$script2 --chroot
  rm $chroot/$script2

  echo "${m}Unmounting partitions...${n}"
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
  echo "${m}Setting timezone to '${i}$timezone${m}'${n}"
  ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
  hwclock --systohc --utc


  ## SET TIME SYNC (optional)
  echo "${m}Enabling time synchronization...${n}"
  systemctl enable systemd-timesyncd


  ## SET LOCALE (required)
  echo "${m}Setting locale to '${i}$locale${m}'${n}"
  sed -i "/$locale.UTF-8/s/^#//g" /etc/locale.gen
  locale-gen
  echo "LANG=$locale.UTF-8" > /etc/locale.conf


  ## SET KEYMAP (required)
  echo "${m}Setting keymap to '${i}$keymap${m}'${n}"
  echo "KEYMAP=$keymap" > /etc/vconsole.conf


  # SET CONSOLE FONT (optional)
  echo "${m}Setting font to '${i}$vcfont${m}'${n}"
  echo "FONT=$vcfont" >> /etc/vconsole.conf


  # SET HOSTNAME (required)
  echo "${m}Setting hostname to '${i}$hostname${m}'${n}"
  echo $hostname > /etc/hostname


  # WRITE HOSTS FILE (required)
  echo "${m}Writing '${i}/etc/hosts${m}'...${n}"
  echo "127.0.0.1  localhost" > /etc/hosts
  echo "::1        localhost" >> /etc/hosts
  echo "127.0.1.1  $hostname.localdomain  $hostname" >> /etc/hosts


  ## ENABLE SERVICES (optional)
  # all services required by penguin-desktop automatically started

#  echo "${m}Enabling TLP service...${n}"
#  systemctl enable tlp

#  echo "${m}VirtualBox guest service...${n}"
#  systemctl enable vboxservice


  ## INSTALL BOOTLOADER (required)
  echo "${m}Configuring bootloader...${n}"

  # BIOS\MBR
  grub-install \
    --target=i386-pc \
    $rootdev

#  # UEFI\GPT
#  grub-install \
#    --target=x86_64-efi \
#    --efi-directory=/boot \
#    --recheck \
#    $rootdev

  grub-mkconfig -o /boot/grub/grub.cfg


  ## ADD USERS (optional)
  if [[ -n $newuser ]]
  then
    echo "${m}Adding user '${i}$newuser${m}'${n}"
    # wheel group gets sudo NOPASSWD
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
  if read -q REPLY\?"Would you like to reboot now? (y/n)"
  then
    reboot
  else
    echo "${m}Continuing with live system, reboot when ready!${n} "
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
