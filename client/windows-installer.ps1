# windows installer

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [String]$Login,
    [Parameter(Mandatory = $true)]
    [String]$Domain,
    [Parameter(Mandatory = $false)]
    [String]$FaythePS1 = "./faythe.ps1",
    [Parameter(Mandatory = $false)]
    [String]$TrustedHostCA = $null
)

if ( -not ( $env:Path | select-string "openssh" ) -and ( [System.Environment]::GetEnvironmentVariable("Path", "Machine") ) ) {
    Write-Host @"
Whilst SSH appears to be installed, it isn't yet in your path - please logout, then login and try again.
"@
    return
}

if ( -not ( Get-Command -Name ssh -Type Application -ErrorAction SilentlyContinue ) ) {
    Write-Host @"
You don't have OpenSSH installed (or in the PATH). Please open an administrative Powershell window and run

    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
    Set-Service -Name ssh-agent -StartupType Automatic

Then re-run this script.
"@
    return
}
else {
    Write-Verbose "OpenSSH installed."
}

if ( -not ( ( Get-Service ssh-agent | Select-Object -ExpandProperty StartType ) -eq "Automatic" ) ) {
    Write-Host @"
Your ssh-agent isn't set to run automatically - please open an administrative PowerShell window and run

    Set-Service -Name ssh-agent -StartupType Automatic

Then re-run this script.
"@
    return
}
else {
    Write-Verbose "ssh-agent set to run OK."
}

if ( -not ( ( Get-Service ssh-agent | Select-Object -ExpandProperty Status ) -eq "Running" ) ) {
    Write-Host @"
Your ssh-agent isn't running. In a normal Powershell window, please run

    Start-Service -name ssh-agent

Then re-run this script.
"@
    return
}
else {
    Write-Verbose "ssh-agent running."
}

if ( -not ( Test-Path ~/.ssh -PathType Container ) ) {
    Write-Host "Creating ~/.ssh folder."
    New-Item -Path ~/.ssh -ItemType Container
}
else {
    Write-Verbose "$HOME/.ssh folder present."
}

if ( -not ( Test-Path ~/.ssh/id_ed25519 ) ) {
    Write-Host @"
Please run:

    ssh-keygen -t ed25519 -f $HOME/.ssh/id_ed25519_$Domain -C "$Login@$Domain faythe key"

and use a strong memorable password. Then re-run this script.
"@
    return
}
else {
    Write-Verbose "id_ed25519_$Domain key present."
}

# check key has a passphrase
ssh-keygen -p -f $HOME/.ssh/id_ed25519_$Domain -N '""' -P '""' 2>&1 | Out-Null
if ( $? -eq $true ) {
    Write-Host @"
Your ssh key doesn't have a passphrase - for security please add one using

    ssh-keygen -p -f $HOME/.ssh/id_ed25519_$Domain

and re-run this script when complete.
"@
    return
}
else {
    Write-Verbose "id_ed25519_$Domain has some sort of passphrase."
}

$fingerprint = $( ssh-keygen -l -f $HOME/.ssh/id_ed25519_$Domain )

if ( -not ( ssh-add -l | Select-String -SimpleMatch "$fingerprint" ) ) {
    Write-Host @"
Please run

    ssh-add -k $HOME/.ssh/id_ed25519_$Domain

to load your key into your keychain, then re-run this script when complete.
"@
    return
}
else {
    Write-Verbose "ssh-key loaded."
}

if ( ( Test-Path -Path $PROFILE -PathType Leaf ) ) {
    # check if it contains source

    if ( -not ( Select-String -Path $PROFILE -Pattern '(?i)^\. \$env:APPDATA/faythe/faythe.ps1') ) {
        '. $env:APPDATA/faythe/faythe.ps1' | Out-File -Append $PROFILE
    }

    if ( -not ( Select-String -Path $PROFILE -Pattern "(?i)Set-Alias -Name ssh -Value fssh") ) {
        "Set-Alias -Name ssh -Value fssh" | Out-File -Append $PROFILE
    }

    if ( -not ( Select-String -Path $PROFILE -Pattern "(?i)Set-Alias -Name scp -Value fscp") ) {
        "Set-Alias -Name scp -Value fscp" | Out-File -Append $PROFILE
    }
}
else {
    Write-Host "Creating $PROFILE"

    $ProfileDir = Split-Path $PROFILE

    if ( -not ( Test-Path $ProfileDir -Type Container ) ) {
        New-Item -Path $ProfileDir -ItemType Container 
    }

    @'
# source faythe function
. $env:APPDATA/faythe/faythe.ps1
Set-Alias -Name ssh -Value fssh
Set-Alias -Name scp -Value fscp
'@ | Out-File -FilePath $PROFILE -Encoding ascii 
}

if ( -not ( Test-Path -Path $env:APPDATA/faythe/domains -PathType Leaf ) ) {
    if ( -not ( Test-Path -Path $env:APPDATA/faythe -PathType Container ) ) {
        New-Item -Path $env:APPDATA/faythe -ItemType Container
    }
    Write-Host "Created $env:APPDATA/faythe/domains"
    @"
# Config file for SSH CA
# format - line containing 3 fields
# 1. domain
# 2. login
# 3. ssh private key file
$Domain $Login ~/.ssh/id_ed25519_$Domain
"@ | Out-File -FilePath $env:APPDATA/faythe/domains -Encoding ascii
}

Write-Host "Creating/updating $env:APPDATA/faythe/faythe.ps1"

if ( -not ( Test-Path $faythePS1 -PathType Leaf ) ) {
    Write-Host "${faythePS1}: file not found."
    return
} 
else {
    New-Item $env:APPDATA/faythe -Type Directory -ErrorAction SilentlyContinue
    Copy-Item $FaythePS1 $env:APPDATA/faythe/faythe.ps1
    Write-Verbose "Copied faythe.ps1 to $env:APPDATA/faythe"
}

Write-Host "Checking SSH config ..."

$sshConfigFile = @"
# ssh basic config file for remote access

# bypass the proxy for these two
Host sshca.$Domain sshgw.$Domain sshenrol.$Domain
    User $login
    IdentityFile ~/.ssh/id_ed25519_$Domain
    ProxyJump none

# anything else @ $Domain, use standard settings
Host *.$Domain
    IdentityFile ~/.ssh/id_ed25519_$Domain
    ForwardAgent yes
    User $login
    ProxyJump ${login}@sshgw.$Domain
"@

if ( -not ( Test-Path -Path "${HOME}/.ssh" -PathType Container ) ) {
    Write-Host "Creating ${HOME}/.ssh"
    New-Item -Path "${HOME}/.ssh" -ItemType Container
}

if ( -not ( Test-Path -Path "${HOME}/.ssh/config" ) ) {
    Write-Host "Creating ${HOME}/.ssh/config"
    $sshConfigFile | Out-File -FilePath ${HOME}/.ssh/config -Encoding ascii
}
else {
    Write-Host @"
Modify your ~/.ssh/config - it needs sections that look like:-

$sshConfigFile
"@
}

if ( $null -ne $TrustedHostCA ) {
    if ( -not ( Test-Path -Path ~/.ssh/known_hosts ) -or -not ( Select-String -Path ~/.ssh/known_hosts "$TrustedHostCA" -SimpleMatch ) ) {
        Write-Host "Added domain trusted host CA to ${HOME}/.ssh/known_hosts"
        @"
# trusted SSH CA for $Domain
$TrustedHostCA
"@ | Out-File -FilePath ~/.ssh/known_hosts -Append -Encoding ascii
    }
}

Write-Host "Update complete."

& cmd /c pause