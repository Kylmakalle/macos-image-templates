export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export BASH_SILENCE_DEPRECATION_WARNING=1
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

if [ $(uname -m) == "x86_64" ]; then
    # NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "/usr/local/opt/nvm/nvm.sh" ] && . "/usr/local/opt/nvm/nvm.sh"
else
    # Brew
    eval "$(/opt/homebrew/bin/brew shellenv)"
    # NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"
fi

# Rbenv
eval "$(rbenv init -)"

# Pyenv
eval "$(pyenv init -)"

eval `/usr/libexec/path_helper -s`