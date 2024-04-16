export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export ZSH=~/.oh-my-zsh
export MANPATH="/usr/local/man:$MANPATH"
export SSH_KEY_PATH="~/.ssh/rsa_id"
export EDITOR='vim'

ZSH_THEME="candy"
DISABLE_AUTO_UPDATE="true"
COMPLETION_WAITING_DOTS="true"

# DISABLE_UNTRACKED_FILES_DIRTY="true"
# HIST_STAMPS="mm/dd/yyyy"

plugins=(git fzf autojump sudo)
source $ZSH/oh-my-zsh.sh

alias qping='ping -i 0.1'
export LANG=en_US
export LC_CTYPE=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export TZ='Asia/Hong_Kong'

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
# rust
[ -f ~/.cargo/env ] && source ~/.cargo/env

[ `command -v bat` ] && alias cat='bat --paging=never --wrap=never --style=header,grid' && export MANPAGER="sh -c 'col -bx | bat -l man -p'"
[ `command -v batcat` ] && alias cat='batcat --paging=never --wrap=never --style=header,grid' && export MANPAGER="sh -c 'col -bx | batcat -l man -p'"
[ `command -v delta` ] && alias diff='delta'
[ `command -v rg` ] && alias grep='rg'
[ `command -v prettyping` ] && alias ping='prettyping --nolegend -i 0.2'

bindkey '^H' backward-kill-word

setopt nocorrectall

autoload -Uz compinit
compinit

# kubectl 
[ `command -v kubectl` ] && source <(kubectl completion zsh)
[ `command -v helm`]  && source <(helm completion zsh)
