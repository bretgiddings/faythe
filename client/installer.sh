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
    echo "+ Creating ${HOME}/.ssh directory"
    mkdir ~/.ssh
    chmod 700 ~/.ssh
fi

if [ ! -f ~/.ssh/id_ed25519_$domain ]; then
    echo "+ Running ssh-keygen - use a memorable passphrase and make a note of it."

    ssh-keygen -q -t ed25519 -f ~/.ssh/id_ed25519_$domain
fi

if ssh-keygen -p -f ~/.ssh/id_ed25519_$domain -N '' -P '' >/dev/null 2>&1; then
    echo "Your SSH key (~/.ssh/id_ed25519_$domain doesn't have a passphrase, please add one using
ech
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

    echo "+ Adding your key to your agent ... use the same passphrase as above."
    ssh-add -k${extra} $HOME/.ssh/id_ed25519_$domain
fi

if [ ! -d ~/.config/faythe ]; then
    echo "+ Creating ~/.confg/faythe directory."
    
    mkdir -p ~/.config/faythe
fi

if [ ! -f ~/.config/faythe/domains ]; then
    echo "+ Creating ~/.config/faythe/domains for essex.ac.uk"
    cat > ~/.config/faythe/domains <<EOF
# Config file for SSH CA
# format - line containing 3 fields
# 1. domain
# 2. login
# 3. ssh private key file
$domain $login ~/.ssh/id_ed25519_$domain
EOF
fi

echo "+ Installing current version of faythe.sh"
cp /tmp/faythe.sh ~/.config/faythe/faythe.sh

echo "+ Checking your ~/.ssh/config file ..."

sshConfig="# ssh basic config file for remote access

# bypass the proxy for these three
Host sshca.$domain sshgw.$domain sshenrol.$domain $noproxy
    User $login
    ProxyJump none

Match Host !sshgw.$domain,!sshca.$domain,*.$domain !exec "ssh-keyscan -T 1 %h >~/.ssh/junk 2>&1"
    ProxyJump ${login}@sshgw.$domain

# anything else @ $domain, use standard settings
Host *.$domain
    IdentityFile ~/.ssh/id_ed25519_$domain
    ForwardAgent yes
    User $login
"
if [ ! -f ~/.ssh/config ]; then
    echo "+ Creating ~/.ssh/config ..."
    echo "$sshConfig" > ~/.ssh/config
    chmod 0600 ~/.ssh/config
else
    echo "+ Please modify your config to include ...

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

# determine environment for . file stuff ...

unameOut="$( uname -s )"
case "$unameOut" in
    Linux*)     osEnv=Linux
                ;;
    Darwin*)    osEnv=Mac
                ;;
    CYGWIN*)
        osEnv=Cygwin
        if [ ! -f $HOME/.bash_profile ]; then
            touch $HOME/.bash_profile
            chmod +x $HOME/.bash_profile
        fi

        if egrep -q '^. $HOME/.config/faythe/faythe.sh' $HOME/.bash_profile; then
            echo "+ Custom script already in .bash_profile"
        else
            echo "+ Adding '. \${HOME}/.config/faythe/faythe.sh' to $HOME/.bash_profile"
            printf -- "\n# Added by faythe installer\n. \${HOME}/.config/faythe/faythe.sh" >> $HOME/.bash_profile
        fi

        ;;
    MINGW*)     osEnv=MinGw
                ;;
    *)          osEnv="UNKNOWN:${unameOut}"
esac

echo "+ Enrolling your SSH public key."
/usr/bin/ssh ${login}@sshenrol.$domain "$(cat ${HOME}/.ssh/id_ed25519_${domain}.pub)"

# 
echo "+ Enabling new functions ..."
exec $SHELL