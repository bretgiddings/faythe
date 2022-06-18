The SSHGW is really just some minor configuration in /etc/ssh/sshd_config. Adding the following *after* the standard sftp subsystem line is the main config change:

```
# if we get a connection for user x and that users
# presents a CA signed key containing principal x
# then this is allowed
TrustedUserCAKeys               /etc/ssh/trustedcas
# otherwise, don't allow an authorized_keys file
# unless overridden
AuthorizedKeysFile              none

# only allow members of the following groups
AllowGroups root ssh-gw-users

# then for root, allow based on authorized_keys
Match user root
   AuthorizedKeysFile ~/.ssh/authorized_keys

# belt and braces for next section
AllowTCPForwarding              no

# and for members of ssh-gw-users (derived
# from openvpn data), apply the following
Match group ssh-gw-users
    # this can be used to validate the key ID is being used from the same IP it was assigned from
    #AuthorizedPrincipalsCommand     /some/path/authorizedprincipals %u %i
    AuthorizedPrincipalsCommandUser root
    PubkeyAuthentication            yes
    PasswordAuthentication          no
    GatewayPorts                    no
    AllowTcpForwarding              yes
    HostbasedAuthentication         no
    AllowAgentForwarding            yes
    X11Forwarding                   yes
    Banner                          none
    ForceCommand                    /bin/false

# and finally, this ought to have a match
# section for all users of ssh-gw-users
# since it is also derived from openvpn
# data.
Include /etc/ssh/sshgw.users
```

The file /etc/ssh/sshgw.users can then be build by hand or script to contain stanzas like

```
Match user user1
    PermitOpen sshhost.example.org:22 intra.example.org:443 rdphost.example.org:3389
```

Note that the user won't be prompted for credentials as this setup uses only trusted, signed certificates and they can only connect to hosts/ports specified in their matching user block (see *man sshd_config* for details). They may or may not be prompted for credentials on the target.

For non-ssh connections such as rdphost.example.org:3389, the user can establish the tunnel

```
ssh -N -L localhost:3389:rdphost.example.org:3389 user1@sshgw.example.org
```

Then connect with their rdp client to localhost:3389.