#!/usr/bin/env zsh

# install.zsh

###############################################################################

# WILL USE ENTIRE DISK
rootdev=/dev/sda

# mount point for chroot
chroot=/mnt

# settings for new systems
newuser="spider"
hostname="setup123"
keymap="us"
vcfont="default8x16"
locale="en_US"
timezone="America/Chicago"

# minimal X install, i3, urxvt, netsurf
packages=(
  penguin-base
  linux base base-devel grub efibootmgr
  dhcpcd openssh ufw fail2ban sudo vi git
  tmux vim zsh curl man-db man-pages
  xorg xorg-drivers xorg-apps xorg-xdm
  i3-wm i3status i3lock-color xss-lock
  rxvt-unicode dmenu netsurf ttf-dejavu
)

# custom package list
# overwrites $packages, make sure you have what you need
custom=${0:A:h}/packages.txt

# settings for post-install
repo="custom"
repodir="$HOME/Packages"
build=${0:A:h}/build.txt
pkgbuilds="https://code.linuxit.us/pkgbuilds"

###############################################################################

exit 1 # comment this line or the script won't run

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
  parted --script $rootdev \
    mklabel gpt \
    mkpart primary fat32 1MiB 260MiB \
    set 1 esp on \
    mkpart primary linux-swap 260MiB 4356MiB \
    mkpart primary xfs 4356MiB 100%

  local boot="${rootdev}1"
  local swap="${rootdev}2"
  local root="${rootdev}3"

  echo "${m}Formatting partitions...${n}"
  mkfs.vfat $boot
  mkfs.xfs -f $root
  mkswap $swap

  echo "${m}Mounting partitions...${n}"
  mkdir -p $chroot
  mount $root $chroot
  mkdir -p $chroot/boot
  mount $boot $chroot/boot
  swapon $swap
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
  echo "LC_COLLATE=C" >> /etc/locale.conf
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

  echo "${m}Enabling DHCP service...${n}"
  systemctl enable dhcpcd

  echo "${m}Enabling SSH service...${n}"
  systemctl enable sshd

  echo "${m}Enabling display manager...${n}"
  systemctl enable xdm

  echo "${m}Configuring default window manager...${n}"
  cat >/etc/skel/.xinitrc <<EOF
#!/bin/bash

xrdb -merge .Xresources

xsetroot -solid grey20

exec i3
EOF
  chmod +x /etc/skel/.xinitrc
  cat >/etc/skel/.Xresources <<EOF
URxvt*background: black
URxvt*foreground: gray
URxvt*font: xft:DejaVu Sans Mono:size=9
EOF

  echo "${m}Configuring bootloader...${n}"
  grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot \
    --recheck \
    $rootdev
  grub-mkconfig -o /boot/grub/grub.cfg

  if [[ -n $newuser ]]
  then
    echo "${m}Adding user '${i}$newuser${m}'${n}"
    useradd -m $newuser
    echo "${m}Set password for '${i}$newuser${m}'${n}"
    passwd $newuser
    echo "$newuser ALL=(ALL:ALL) ALL" >> /etc/sudoers
    grpck
    cp $script /home/$newuser/$script
    chown $newuser:$newuser /home/$newuser/$script
  fi

  echo "${m}Set password for '${i}root${m}'${n}"
  passwd || { echo "${e}NO ROOT PASSWORD IS DANGEROUS!${n}"; passwd }

  return
}

# stage3 installs aurutils and packages
function stage3 {

  echo "${m}Building extra software from AUR and git repo${n}"

  [[ $user == 0 ]] && { echo "${e}Don't run as root!${n}"; exit 1 }

  echo "${m}Checking for aurutils...${n}"
  if (( ! $+commands[aur] ))
  then
    echo "${i}Installing aurutils...${n}"
    local url="https://aur.archlinux.org/aurutils"
    local temp=$(mktemp -d)

    git clone $url $temp
    cd $temp
    makepkg -sric --noconfirm --skippgpcheck --needed
    cd ${script:A:h}
    rm -rf $temp

    unset temp
  fi

  echo "${m}Setting up repo '${i}$repo${m}'${n}"
  mkdir -p $repodir
  cd $repodir
  repo-add -q $repo.db.tar
  cd ${script:A:h}

  local userconf=$HOME/.pacman.conf
  local sysconf=/etc/pacman.conf

  echo "${m}Writing $userconf...${n}"
  echo "[${repo}]" >! $userconf
  echo "SigLevel = Optional TrustAll" >> $userconf
  echo "Server = file://$repodir" >> $userconf

  echo "${m}Writing $sysconf...${n}"
  echo "Include = $userconf" | \
    sudo tee -a $sysconf >/dev/null

  unset userconf sysconf

  echo "${m}Update pacman cache...${n}"
  sudo pacman -Sy

  echo "${m}Checking for build.txt...${n}"
  if [[ -f $build ]]
  then
    echo "${i}Processing build list...${n}"
    local -a pkg

    while read -r pkg
    do
      pacman -Q $pkg &>/dev/null && continue
      aur sync --no-view --noconfirm $pkg
    done < $build
  fi

  unset pkg

  echo "${m}Checking for git repo...${n}"
  if [[ -n $pkgbuilds ]]
  then
    echo "${i}Building git repo '${i}$pkgbuilds${m}'${n}"
    local temp=$(mktemp -d)
    local src
    git clone $pkgbuilds $temp

    setopt nullglob
    for src in $temp/*(/)
    do
      cd $src
      aur build -f -- -sric --noconfirm
    done

    rm -rf $temp
    unsetopt nullglob
    unset temp src
  fi

  echo "${m}Done${n}"
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
    echo "  -ps | --post-install      run stage3, install aurutils, pkgbuilds"
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
  -ps | --post-install)
    stage3
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
