#!/bin/bash

# taken from https://unix.stackexchange.com/a/421403
bashget() {
  read proto server path <<<"${1//"/"/ }"
  DOC=/${path// //}
  HOST=${server//:*/}
  PORT=${server//*:/}
  [[ "${HOST}" == "${PORT}" ]] && PORT=80

  exec 3<>/dev/tcp/${HOST}/$PORT

  # send request
  echo -en "GET ${DOC} HTTP/1.0\r\nHost: ${HOST}\r\n\r\n" >&3

  # read the header, it ends in a empty line (just CRLF)
  while IFS= read -r line; do
    [[ "$line" == $'\r' ]] && break
  done <&3

  # read the data
  nul='\0'
  while IFS= read -d '' -r x || {
    nul=""
    [ -n "$x" ]
  }; do
    printf "%s$nul" "$x"
  done <&3
  exec 3>&-
}

set -xeo pipefail

function PMDetect() {
  if (which apt-get >/dev/null); then
    PM=apt-get
    if ! [ "$(command -v lsb_release)" ]; then
      LSB=unknown
      return
    fi
    lsbd=$(lsb_release -d)
    case "$lsbd" in
    *Debian*)
      LSB=debian
      ;;
    *Ubuntu*)
      LSB=ubuntu
      ;;
    *)
      echo "Unable to detect your lsb release."
      LSB=unknown
      ;;
    esac
  elif (which yum >/dev/null); then
    PM=yum
  fi
  if [ "$PM" == "" ]; then
    echo "Nither apt-get nor yum is found."
    exit 1
  fi
}

end="\033[0m"
blue="\033[0;34m"

# Functions
function ensureLoc() {
  if [ "$LOC" == "" ]; then
    if (which curl >/dev/null); then
      LOC=$(curl -m 5 -s http://cf-ns.com/cdn-cgi/trace | grep loc | cut -c 5-)
    elif (which wget >/dev/null); then
      LOC=$(wget --timeout=5 -O- http://cf-ns.com/cdn-cgi/trace | grep loc | cut -c 5-)
    else
      LOC=$(bashget http://cf-ns.com/cdn-cgi/trace | grep loc | cut -c 5-)
    fi
  fi
}

function installPackage() {
  $PM install -y "$@"
}

function installPackageYumOnly() {
  if [ "$PM" == "yum" ]; then
    yum install -y "$@"
  fi
}

function installPackageAptOnly() {
  if [ "$PM" == "apt-get" ]; then
    apt-get install -y "$@"
  fi
}

function purgePackageAptOnly() {
  if [ "$PM" == "apt-get" ]; then
    apt-get purge -y "$@"
  fi
}

function suckIPv6() {
  if [ "$LOC" == CN ]; then
    echo -e "\nNot in CN, not disabling IPV6, return..."
    return
  fi
  if [ "$PM" == "apt-get" ]; then
    echo 'Acquire::ForceIPv4 "true";' >/etc/apt/apt.conf.d/99force-ipv4
  elif [ "$PM" == "yum" ]; then
    sed -i 's/^ip_resolve/#ip_resolve/g' /etc/yum.conf
    echo 'ip_resolve=4' >>/etc/yum.conf
  fi
}

function fastDebMirror() {
  ensureLoc
  if [ "$LOC" == CN ]; then
    [ $SEI_BACKUP ] && cp /etc/apt/sources.list ~/.seinit/sources.list
    if [ "$LSB" == "ubuntu" ]; then
      # sed -i 's#^deb [^ ]* #deb mirror://mirrors.ubuntu.com/mirrors.txt #g' /etc/apt/sources.list
      sed -i 's#/archive.ubuntu.com/#/mirrors.ustc.edu.cn/#g' /etc/apt/sources.list
      sed -i 's#/cn.archive.ubuntu.com/#/mirrors.ustc.edu.cn/#g' /etc/apt/sources.list
    elif [ "$LSB" == "debian" ]; then
      sed -i 's#/deb.debian.org/#/mirrors.ustc.edu.cn/#g' /etc/apt/sources.list
      if [ -e /etc/apt/mirrors/debian.list ]; then
        echo https://mirrors.ustc.edu.cn/debian >/etc/apt/mirrors/debian.list
      fi
      if [ -e /etc/apt/mirrors/debian-security.list ]; then
        echo https://mirrors.ustc.edu.cn/debian-security >/etc/apt/mirrors/debian-security.list
      fi
    fi
  fi
}

function updatePMMetadata() {
  if [ "$PM" == "apt-get" ]; then
    fastDebMirror
    apt-get update
  elif [ "$PM" == "yum" ]; then
    yum makecache
  fi
}

function importSSHKeys() {
  [ -d ~/.ssh ] || mkdir ~/.ssh
  ensureLoc
  if [ "$LOC" == CN ]; then
    curl -L https://www.starduster.me/ssh.key >>~/.ssh/authorized_keys
  else
    curl -L https://github.com/starduster.keys >>~/.ssh/authorized_keys
  fi
  chmod 600 ~/.ssh/authorized_keys
}

function changeSSHPort() {
  local PORT=$1
  sed -i 's/^ListenAddress/#ListenAddress/g' /etc/ssh/sshd_config
  sed -i 's/^Port/#Port/g' /etc/ssh/sshd_config
  echo '# sei init changed ssh port' >>/etc/ssh/sshd_config
  echo "Port $PORT" >>/etc/ssh/sshd_config
}

function changePassword() {
  echo "$(whoami):fai" | chpasswd
}

function disableSSHRootLoginWithPassword() {
  sed -i 's/^PermitRootLogin/#PermitRootLogin/g' /etc/ssh/sshd_config
  {
    echo '# sei init disabled root login with password'
    echo "PermitRootLogin without-password"
  } >>/etc/ssh/sshd_config
}

function enhanceSSHConnection() {
  sed -i 's/^TCPKeepAlive/#TCPKeepAlive/g' /etc/ssh/sshd_config
  sed -i 's/^ClientAliveInterval/#ClientAliveInterval/g' /etc/ssh/sshd_config
  sed -i 's/^ClientAliveCountMax/#ClientAliveCountMax/g' /etc/ssh/sshd_config
  {
    echo '# sei init disabled enhance SSH connection'
    echo "TCPKeepAlive yes"
    echo "ClientAliveInterval 30"
    echo "ClientAliveCountMax 3"
  } >>/etc/ssh/sshd_config
}

function restartSSHService() {
  service sshd restart || service ssh restart
}

function installOmz() {
  if [ -d ~/.oh-my-zsh ]; then
    echo -e "oh-my-zsh exists, skip...\n"
    return 0
  fi
  ensureLoc
  if [ "$LOC" == CN ]; then
    export REMOTE=https://git.atto.town/public-mirrors/oh-my-zsh.git
  fi
  curl https://git.atto.town/public-mirrors/oh-my-zsh/-/raw/master/tools/install.sh | grep -v 'env zsh' | bash
  [ $SEI_BACKUP ] && cp ~/.zshrc ~/.seinit/dot_zshrc
  wget https://raw.githubusercontent.com/StarDuster/init.sh/master/dotfiles/.zshrc -O ~/.zshrc
  wget https://raw.githubusercontent.com/StarDuster/Personal-script/master/stardust.zsh-theme -O ~/.oh-my-zsh/themes/stardust.zsh-theme
}

function updateVimRc() {
  ensureLoc
  if [ "$LOC" == CN ]; then
    curl https://raw.githubusercontent.com/StarDuster/init.sh/master/dotfiles/.vimrc >~/.vimrc
  else
    curl https://cdn.jsdelivr.net/gh/starduster/init.sh@master/dotfiles/.vimrc >~/.vimrc
  fi
}

function updateSystemVimRc() {
  {
    echo "source \$VIMRUNTIME/defaults.vim"
    echo "let g:skip_defaults_vim = 1"
    echo "set mouse="
    echo "set ttymouse="
  } >>/etc/vim/vimrc.local
}

function ensureLocale() {
  LC_ALL=$(locale -a | grep -ix 'c.utf-\?8' || echo C)
  export LC_ALL
  localedef -i en_US -f UTF-8 en_US.UTF-8
}

function help() {
  echo -e "# ${blue}installPackage${end} - Install package"
  echo -e "# ${blue}suckIPv6${end} - Disable IPv6"
  echo -e "# ${blue}updatePMMetadata${end} - Update package manager metadata"
  echo -e "# ${blue}importSSHKeys${end} - Import SSH keys"
  echo -e "# ${blue}installByobu${end} - Install byobu"
  echo -e "# ${blue}changeSSHPort 33${end} - Change SSH port to 33"
  echo -e "# ${blue}changePassword${end} - Change password to fai"
  echo -e "# ${blue}disableSSHRootLoginWithPassword${end} - Disable SSH root login with password"
  echo -e "# ${blue}enhanceSSHConnection${end} - Enable SSH TCPKeepAlive stuff"
  echo -e "# ${blue}restartSSHService${end} - Restart SSH server"
  echo -e "$ ${blue}installOmz${end} - Install Oh-my-zsh"
  echo -e "$ ${blue}updateVimRc${end} - Update .vimrc"
}

SEI_BACKUP=yes
if [ $SEI_BACKUP ]; then
  [ -d ~/.seinit ] || mkdir ~/.seinit
  chmod 700 ~/.seinit
fi
if [ "$(whoami)" == "root" ]; then
  suckIPv6
  PMDetect
  updatePMMetadata
  if [ "$LSB" == "ubuntu" ]; then
    purgePackageAptOnly needrestart snapd netplan
  fi
  installPackageYumOnly epel-release
  installPackage zsh fzf nethogs wget curl git htop ncdu vim rsync cron iftop tree screen vnstat locales iptables
  ensureLocale
  SEI_FUCK_SSH=yes
  if [ "$SEI_FUCK_SSH" == "yes" ]; then
    if [ -f "/etc/ssh/sshd_config" ]; then
      [ $SEI_BACKUP ] && cp /etc/ssh/sshd_config ~/.seinit/sshd_config
        disableSSHRootLoginWithPassword
        enhanceSSHConnection
        restartSSHService
    else
      echo -e "\033[0;31m/etc/ssh/sshd_config does not exist. Please install openssh server.\033[0m"
      return
    fi
  fi
  updateSystemVimRc
  if (which update-alternatives >/dev/null); then
    update-alternatives --set editor /usr/bin/vim.basic
  fi
  importSSHKeys
  [ -f /etc/default/motd-news ] && sed -i 's/ENABLED=./ENABLED=0/' /etc/default/motd-news
  [ -d /etc/update-motd.d ] && chmod o-x,g-x,a-x /etc/update-motd.d/*
  installPackageAptOnly build-essential bat eatmydata ripgrep fzf autojump tcpdump iperf3 man-db rsyslog mtr-tiny expect whois
  installPackageAptOnly software-properties-common || true
  installPackageAptOnly python-software-properties || true
  changePassword
  installOmz
  set +x
  echo "--- Seinit finish its work now. ---"
else
  chsh -s /usr/bin/zsh
  installOmz
fi
