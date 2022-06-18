# Concepts

It is assumed that you are already managing the users on at least the sshca server by some means. Users should have a valid shell (a requirement of SSH forced-commands) but they don't have interactive login rights. They do not require a valid home-directory path since they don't have interactive login rights. Both ssh (via forced-commands) and pam (via google-authenticator) use a server-only directory to manage the users' mfa codes. However, it is assumed that the system can authenticate the user password - either through local shadow password or kerberos.

To enrol a new user, the newuser script creates a psuedo _home_ directory for the named user and adds the user to the _faythe-enrol_ group and adds a file called _enrol_ in their directory containing an enrollment token (a random UUID). This should be communicated to the user via secure means - ideally text or non-instiutional email address.

Once the user receives the enrollment token, they can login using _user@sshenrol.example.org_ - this will prompt for their password, then UUID. Assuming that these are correct, they will then be prompted for a copy of their public key (_ed25519_ or _rsa_). Assuming a correcty formatted public key is provided and validated, a QR code will be displayed and the user can use _authy_, _google-authenticator_ or _microsoft authenticator_ to scan the QR code add a new MFA source. 

For users who have enrolled, assuming that they have configured their SSH environment, they can just use _ssh host.example.org_ to connect. If they don't have a valid signed copy of their public key, they will be redirected to _sshca.example.org_ which will prompt for password and mfa code. Assuming these are correct, the a time-limited (default 1 day) signed copy of the users public key will be returned. Note also that the same keypair must also be used for the signing process - it is assumed that the user has this passphrase protected and maybe stored in an agent - so there may be an additional prompt for the private key passphrase. The user will then be logged in to _ssh host.example.org_ with the signed public key present. However, if they do have a valid signed copy of their public key, they are logged in direct. In an ideal world, any hosts in example.org would trust signed certificates from _sshca.examples.org_ (maybe subject to principals in the certificate) to make access transparent.

# Additional system modifications

## Packages

Ensure that the following packages are installed.

* libpam-google-authenticator
* sudo
* bsdutils
* uuid
* qrencode

## sshd_config

* Set ChallengeResponseAuthentication yes
* Add match sections (probably at the end of the file) and change $INSTALL_ROOT to match variable in INSTALL.sh


```
Match Group faythe-enrol
  PermitRootLogin no
  PasswordAuthentication yes
  AuthenticationMethods keyboard-interactive
  ForceCommand $INSTALL_ROOT/bin/enrol

Match Group faythe-users
  PermitRootLogin no
  PasswordAuthentication yes
  AuthenticationMethods keyboard-interactive
  ForceCommand $INSTALL_ROOT/bin/reissue
```

Followed by _systemctl restart ssh_

## /etc/pam.d/sshd

Add after _@common_auth_ and change $INSTALL_ROOT as above

```
auth [success=done default=ignore] pam_succeed_if.so user ingroup faythe-enrol
auth required pam_google_authenticator.so secret=$INSTALL_ROOT/users/${USER}/google-authenticator
```

## /etc/sudoers

Add

```
# required for faythe ssh user ca
ALL ALL=(ALL) NOPASSWD: /usr/bin/ssh-keygen
ALL ALL=(ALL) NOPASSWD: /usr/bin/gpasswd
```
