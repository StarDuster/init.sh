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

# PM detect
if (which apt-get >/dev/null); then
  PM=apt-get
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
  if [ $PM == "yum" ]; then
    yum install -y "$@"
  fi
}

function installPackageAptOnly() {
  if [ $PM == "apt-get" ]; then
    apt-get install -y "$@"
  fi
}

function suckIPv6() {
  if [ "$LOC" == CN ]; then
    echo -e "\nNot in CN, not disabling IPV6, return..."
    return
  fi
  if [ $PM == "apt-get" ]; then
    echo 'Acquire::ForceIPv4 "true";' >/etc/apt/apt.conf.d/99force-ipv4
  elif [ $PM == "yum" ]; then
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
  if [ $PM == "apt-get" ]; then
    fastDebMirror
    apt-get update
  elif [ $PM == "yum" ]; then
    yum makecache
  fi
}

function importSSHKeys() {
  [ -d ~/.ssh ] || mkdir ~/.ssh
  mkdir -p ~/.ssh/ && curl -L github.com/starduster.keys >>~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
}

function changeSSHPort() {
  local PORT=$1
  sed -i 's/^ListenAddress/#ListenAddress/g' /etc/ssh/sshd_config
  sed -i 's/^Port/#Port/g' /etc/ssh/sshd_config
  echo '# sei init changed ssh port' >>/etc/ssh/sshd_config
  echo "Port $PORT" >>/etc/ssh/sshd_config
}

function disableSSHRootLoginWithPassword() {
  sed -i 's/^PermitRootLogin/#PermitRootLogin/g' /etc/ssh/sshd_config
  echo '# sei init disabled root login with password' >>/etc/ssh/sshd_config
  echo "PermitRootLogin without-password" >>/etc/ssh/sshd_config
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
  ensureLoc
  if [ "$LOC" == CN ]; then
    export REMOTE=https://git.atto.town/public-mirrors/oh-my-zsh.git
  fi
  curl https://git.atto.town/public-mirrors/oh-my-zsh/-/raw/master/tools/install.sh | grep -v 'env zsh' | bash
  [ $SEI_BACKUP ] && cp ~/.zshrc ~/.seinit/dot_zshrc
}

function updateVimRc() {
  curl https://oott123.urn.cx/seinit/.vimrc >~/.vimrc
}

function updateSystemVimRc() {
  {
    echo "source \$VIMRUNTIME/defaults.vim"
    echo "let g:skip_defaults_vim = 1"
    echo "set mouse="
    echo "set ttymouse="
  } >>/etc/vim/vimrc.local
}

function help() {
  echo -e "# ${blue}installPackage${end} - Install package"
  echo -e "# ${blue}suckIPv6${end} - Disable IPv6"
  echo -e "# ${blue}updatePMMetadata${end} - Update package manager metadata"
  echo -e "# ${blue}importSSHKeys${end} - Import SSH keys"
  echo -e "# ${blue}installByobu${end} - Install byobu"
  echo -e "# ${blue}changeSSHPort 33${end} - Change SSH port to 33"
  echo -e "# ${blue}disableSSHRootLoginWithPassword${end} - Disable SSH root login with password"
  echo -e "# ${blue}enhanceSSHConnection${end} - Enable SSH TCPKeepAlive stuff"
  echo -e "# ${blue}restartSSHService${end} - Restart SSH server"
  echo -e "$ ${blue}installOmz${end} - Install Oh-my-zsh"
  echo -e "$ ${blue}updateVimRc${end} - Update .vimrc"
}

if [ "$SEI_SHELL" == "" ]; then
  # ...
  SEI_BACKUP=yes
  if [ $SEI_BACKUP ]; then
    [ -d ~/.seinit ] || mkdir ~/.seinit
    chmod 700 ~/.seinit
  fi
  if [ "$(whoami)" == "root" ]; then
    if [ "$SEI_FUCK_SSH" == "" ]; then
      read -p "May I FUCK your ssh server? [y/N]" -r
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        SEI_FUCK_SSH=yes
      fi
    fi
    if [ "$SEI_FUCK_SSH" == "yes" ]; then
      [ $SEI_BACKUP ] && cp /etc/ssh/sshd_config ~/.seinit/sshd_config
      # changeSSHPort 33
      disableSSHRootLoginWithPassword
      enhanceSSHConnection
      restartSSHService
    fi
    suckIPv6
    updatePMMetadata
    installPackageYumOnly epel-release
    # installByobu
    installPackage zsh wget curl git htop ncdu vim rsync cron iftop tee tree screen vnstat
    updateSystemVimRc
    if (which update-alternatives >/dev/null); then
      update-alternatives --set editor /usr/bin/vim.basic
    fi
    if [ -f /bin/zsh ]; then
      usermod -s /bin/zsh root
    fi
    importSSHKeys
    [ -f /etc/default/motd-news ] && sed -i 's/ENABLED=./ENABLED=0/' /etc/default/motd-news
    [ -d /etc/update-motd.d ] && chmod o-x,g-x,a-x /etc/update-motd.d/*
    installPackageAptOnly build-essential bat ripgrep fzf autojump tcpdump netcat iperf3 man-db rsyslog mtr-tiny
    installPackageAptOnly software-properties-common || true
    installPackageAptOnly python-software-properties || true
    installOmz
    set +x
    echo "--- Seinit finish its work now. ---"
  else
    installOmz
  fi
elif [ "$SEI_SHELL" == "1" ]; then
  set +x
  set +e
  if [ -f ~/.bashrc ]; then
    source ~/.bashrc
  fi
  PS1="[\u@\h \[\033[41m\]SEI_SHELL\[\033[0m\]]\$> "
  clear
  echo ""
  help
  echo ""
  echo "Type [help] to see what you can do"
  echo "Type [exit] to exit sei shell"
  echo ""
  cd /tmp
fi
