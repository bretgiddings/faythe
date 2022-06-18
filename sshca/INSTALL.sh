#!/bin/sh

INSTALL_ROOT=CHANGEME # e.g /usr/local/faythe

if [ $INSTALL_ROOT = "CHANGEME" ];
    echo Please configure variable INSTALL_ROOT in INSTALL.sh
    exit 1
fi

umask 022
mkdir -p $INSTALL_ROOT
mkdir $INSTALL_ROOT/bin
mkdir $INSTALL_ROOT/users
mkdir $INSTALL_ROOT/ca
mkdir $INSTALL_ROOT/etc
addgroup faythe-enrol

cp gaenrol newuser reissue $INSTALL_ROOT/bin
chmod 755 $INSTALL_ROOT/bin/*

echo "See README.md for instructions on setting up the CA and editing

* /etc/ssh/sshd_config  
  two changes
* /etc/pam.d/ssh  
  1 change
* /etc/sudoers
  1 change
"