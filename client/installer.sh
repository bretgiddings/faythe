#!/bin/sh

usage="usage: $0 --login <login> --domain <domain> --trustedca <trustedca>"

while [ "$#" -gt 0 ]
do
    case "$1" in
        "--login")
            login=$2
            shift 2
            ;;
        "--domain")
            domain=$2
            shift 2
            ;;
        "--trustedhostca")
            trustedHostCA=$2
            shift 2
            ;;
        "--faythescript")
            faythescript=$2
            shift 2
            ;;
        "--noproxy")
            noproxy=$2
            shift 2
            ;;
        *)
            echo $usage
            exit 1
            ;;
    esac
done

: "${login:?Required parameter --login not set.}"
: "${domain:?Required parameter --domain not set.}"
: "${trustedHostCA:?Required paramter --trustedca not set.}"

# installer for linux/mac

SSH=$( ssh -V 2>&1 )

if [ "$SSH" = "${SSH#OpenSSH}" ]; then
    echo "You don't appear to have a standard OpenSSH installed"
    exit 1
fi

if [ -z "$SSH_AUTH_SOCK" ]; then
    echo "Warning: SSH Agent not running" 
fi

if [ ! -d ~/.ssh ]; then
    echo "You don't have a .ssh directory - please create it using

    mkdir ~/.ssh
    chmod 700 ~/.ssh
"
    exit 1
fi

if [ ! -f ~/.ssh/id_ed25519_$domain ]; then
    echo "You don't have a id_ed25519_$domain keypair. Please create one using

ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_$domain
"
    exit 1
fi

if ssh-keygen -p -f ~/.ssh/id_ed25519_$domain -N '' -P '' >/dev/null 2>&1; then
    echo "Your SSH key (~/.ssh/id_ed25519_$domain doesn't have a passphrase, please add one using

ssh-keygen -p -f ~/.ssh/id_ed25519_$domain
"
    exit 1
fi

FINGERPRINT=$( ssh-keygen -l -f ~/.ssh/id_ed25519_$domain )

ssh-add -l | grep -q "$FINGERPRINT"

if [ $? = 1 ]; then
    extra=""
    if [ $( uname ) = "Darwin" ]; then
      extra=" --apple-use-keychain"
    fi

    echo "Your SSH key hasn't been added to your SSH agent - please add using

ssh-add -k${extra} $HOME/.ssh/id_ed25519_$domain
"
    exit 1
fi

if [ ! -d ~/.config/faythe ]; then
    echo "Creating ~/.confg/faythe directory."
    
    mkdir -p ~/.config/faythe
fi

if [ ! -f ~/.config/faythe/domains ]; then
    echo "Creating ~/.config/faythe/domains for essex.ac.uk"
    cat > ~/.config/faythe/domains <<EOF
# Config file for SSH CA
# format - line containing 3 fields
# 1. domain
# 2. login
# 3. ssh private key file
$domain $login ~/.ssh/id_ed25519_$domain
EOF
fi

echo "Installing current version of faythe.sh"
cp /tmp/faythe.sh ~/.config/faythe/faythe.sh

echo "Checking your ~/.ssh/config file ..."

sshConfig="# ssh basic config file for remote access

# bypass the proxy for these three
Host sshca.$domain sshgw.$domain sshenrol.$domain $noproxy
    User $login
    ProxyJump none

# anything else @ $domain, use standard settings
Host *.$domain
    IdentityFile ~/.ssh/id_ed25519_$domain
    ForwardAgent yes
    User $login
    ProxyJump ${login}@sshgw.$domain
"
if [ ! -f ~/.ssh/config ]; then
    echo "Creating ~/.ssh/config ..."
    echo "$sshConfig" > ~/.ssh/config
    chmod 0600 ~/.ssh/config
else
    echo "Please modify your config to include ...

$sshConfig
"
fi

if [ -f ~/.ssh/known_hosts ]; then
    grep -q "$trustedHostCA" ~/.ssh/known_hosts
    if [ $? -eq 1 ]; then
        echo "$trustedHostCA" >> ~/.ssh/known_hosts
    fi
else
    echo "$trustedHostCA" >> ~/.ssh/known_hosts
    chmod 600 ~/.ssh/known_hosts
fi