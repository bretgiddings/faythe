#!/usr/bin/env pwsh
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
    [String]$TrustedHostCA = $null,
    [Parameter(Mandatory = $false)]
    [String]$NoProxy = $null
)

if ( -not ( [System.Environment]::OSVersion.Platform -eq "Win32NT" ) ) {
    Write-Host @"
This script is only intended for running on Windows platform.
"@
    return
}

$sshDir = $null

foreach ( $dir in $env:PATH -split [System.IO.Path]::PathSeparator ) {
    if ( ( Test-Path "$dir/ssh.exe" ) -and ( Test-Path "$dir/ssh-keygen.exe" ) ) {
        $sshDir = $dir;
        break
    }
}

if ( $null -eq $sshDir ) {
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
    #Start-Process -Verb RunAs -FilePath Powershell -ArgumentList '/c "Set-Service -Name ssh-agent -Startuptype Automatic"'
    Write-Host @"
Your ssh-agent isn't set to run automatically - please open an administrative PowerShell window and run

    Set-Service -Name ssh-agent -StartupType Automatic

Then re-run this script.
"@
    return
}
else {
    Write-Verbose "ssh-agent set to run Automatically."
}

if ( -not ( ( Get-Service ssh-agent | Select-Object -ExpandProperty Status ) -eq "Running" ) ) {
    Write-host "+ Attempting to start ssh-agent ..."
    Start-Service ssh-agent
    Start-Sleep -Seconds 1;
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

if ( -not ( Test-Path $HOME/.ssh -PathType Container ) ) {
    Write-Host "+ Creating $HOME/.ssh folder."
    New-Item -Path $HOME/.ssh -ItemType Container | Out-Null
}
else {
    Write-Verbose "$HOME/.ssh folder present."
}

$createdKeyPair = $false

if ( -not ( Test-Path $HOME/.ssh/id_ed25519_$Domain ) ) {
    $createdKeyPair = $true
    Write-Host "+ Running ssh-keygen - use a memorable passphrase and make a note of it."
    & ssh-keygen -q -t ed25519 -f "$HOME/.ssh/id_ed25519_$Domain" -C "$Login@$Domain faythe key"
}
else {
    Write-Verbose "id_ed25519_$Domain key present."
}

# check key has a passphrase
& $sshDir/ssh-keygen.exe -p -f $HOME/.ssh/id_ed25519_$Domain -N '""' -P '""' 2>&1 | Out-Null
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

$fingerprint = $( & $sshDir/ssh-keygen.exe -l -f $HOME/.ssh/id_ed25519_$Domain )

if ( -not ( & $sshDir/ssh-add.exe -l | Select-String -SimpleMatch "$fingerprint" ) ) {
    Write-Host "+ Adding your key to your agent ... use the same passphrase as above."
    & ssh-add -k $HOME/.ssh/id_ed25519_$Domain
}

if ( -not ( & $sshDir/ssh-add.exe -l | Select-String -SimpleMatch "$fingerprint" ) ) {
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

    if ( -not ( Select-String -Path $PROFILE -Pattern "(?i)Set-Alias -Name sftp -Value fsftp") ) {
        "Set-Alias -Name sftp -Value fsftp" | Out-File -Append $PROFILE
    }
}
else {
    Write-Host "+ Creating powershell profile $PROFILE"

    $ProfileDir = Split-Path $PROFILE

    if ( -not ( Test-Path $ProfileDir -Type Container ) ) {
        New-Item -Path $ProfileDir -ItemType Container | Out-Null
    }

    @'
# source faythe function
. $env:APPDATA/faythe/faythe.ps1
Set-Alias -Name ssh -Value fssh
Set-Alias -Name scp -Value fscp
Set-Alias -Name sftp -value fsftp
'@ | Out-File -FilePath $PROFILE -Encoding ascii 
}

if ( -not ( Test-Path -Path $env:APPDATA/faythe/domains -PathType Leaf ) ) {
    if ( -not ( Test-Path -Path $env:APPDATA/faythe -PathType Container ) ) {
        New-Item -Path $env:APPDATA/faythe -ItemType Container | Out-Null
    }
    Write-Host "+ Created $env:APPDATA/faythe/domains."
    @"
# Config file for SSH CA
# format - line containing 3 fields
# 1. domain
# 2. login
# 3. ssh private key file
$Domain $Login ~/.ssh/id_ed25519_$Domain
"@ | Out-File -FilePath $env:APPDATA/faythe/domains -Encoding ascii
}

Write-Host "+ Creating/updating $faythePS1."

if ( -not ( Test-Path $faythePS1 -PathType Leaf ) ) {
    Write-Host "${faythePS1}: file not found."
    return
} 
else {
    New-Item $env:APPDATA/faythe -Type Directory -ErrorAction SilentlyContinue | Out-Null
    Copy-Item $FaythePS1 $env:APPDATA/faythe/faythe.ps1 | Out-Null
    Write-Verbose "Copied faythe.ps1 to $env:APPDATA/faythe"
}

Write-Host "+ Checking SSH config ..."

if ( -not ( Test-Path -Path "${HOME}/.ssh" -PathType Container ) ) {
    Write-Host "Creating ${HOME}/.ssh."
    New-Item -Path "${HOME}/.ssh" -ItemType Container | Out-Null
}

if ( -not ( Test-Path -Path "${HOME}/.ssh/config" -PathType Leaf ) ) {
    Write-Host "+ Creating ${HOME}/.ssh/config."
    @"

# generic config for ${Domain} - should come after any other more specialised rules

Match Host *.${Domain}
    Include ~/.ssh/faythe_${Domain}.config

"@ | Out-File -FilePath ${HOME}/.ssh/config -Encoding ascii
}
else {
    if ( -not ( Select-String -Path "${HOME}/.ssh/config" -Pattern "(?i)^\s+Include ~/.ssh/faythe_${Domain}.config" ) ) {
        Write-Host "+ Adding include statement to ${HOME}/.ssh/config"
        @"

# generic config for ${Domain} - should come after any other more specialised rules

Match Host *.${Domain}
    Include ~/.ssh/faythe_${Domain}.config

"@ | Out-File -Append "${HOME}/.ssh/config" -Encoding ascii
    }
}

if ( -not ( Test-Path -Path "${HOME}/.ssh/faythe_${Domain}.config" -PathType Leaf ) ) {
    Write-Host "+ Creating include file ${HOME}/.ssh/faythe_${Domain}.config."
    @"
# faythe include file for domain ${Domain}

# check if we need to route through the gateway 
Match Host !sshgw.${Domain},!sshca.${Domain},!sshenrol.${Domain},*.${Domain} !exec "ssh-keyscan -T 1 %h >%d/.ssh/.junk 2>&1"
    ProxyJump ${login}@sshgw.${Domain}
    ForwardAgent no

# otherwise, use the defaults - if you need to override these
# do this in the main config before this include file is called

Host *.${Domain}
    User $login
    IdentityFile ~/.ssh/id_ed25519_${Domain}
    ForwardAgent yes

"@ | Out-File -FilePath "${HOME}/.ssh/faythe_${Domain}.config" -Encoding ascii
}

if ( $null -ne $TrustedHostCA ) {
    if ( -not ( Test-Path -Path $HOME/.ssh/known_hosts ) -or -not ( Select-String -Path $HOME/.ssh/known_hosts "$TrustedHostCA" -SimpleMatch ) ) {
        Write-Host "+ Added domain trusted host CA to ${HOME}/.ssh/known_hosts."
        @"
# trusted SSH CA for $Domain
$TrustedHostCA
"@ | Out-File -FilePath $HOME/.ssh/known_hosts -Append -Encoding ascii
    }
}

$publicKey = Get-Content -Path $HOME/.ssh/id_ed25519_${Domain}.pub

if ( $true -eq $createdKeyPair ) {
    Write-Host "+ Enrolling your SSH public key."
    & ssh ${Login}@sshenrol.$Domain "$publicKey"
    Write-Host "+ Open a new powershell window to start using ssh."
}

