# script to grab signed ca key if old key has expired

function _faythe {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [String]$cmd
    )

    $cmdPath = ( Get-Command -Name "$cmd" -Type Application -ErrorAction SilentlyContinue )[0].Path

    # belt and braces for when we actually need to run ssh
    $sshPath = ( Get-Command -Name "ssh" -Type Application -ErrorAction SilentlyContinue )[0].Path

    if ( $null -eq $sshPath ) {
        Write-Host -ForegroundColor Red "ssh/scp not found on path - is it installed?"
        return
    }

    $config = "${HOME}/.config/faythe/domains"
    if ( ( Test-Path env:APPDATA ) -and ( Test-Path "$( $env:APPDATA )/faythe/domains" -ErrorAction SilentlyContinue ) ) {
        # on windows 
        $config = "$( $env:APPDATA )/faythe/domains"
    }
    
    foreach ( $line in $( Get-Content $config ) ) {
        $fields = -split $line
        if ( $args -match "\.$( $fields[0] )(\s|:|$)" ) {
            if ( $fields.Count -eq 3 ) {
                Set-Variable -Name domain -Value $fields[0]
                Set-Variable -Name login -Value $fields[1]
                Set-Variable -Name cert -Value ( "$( $fields[2] )-cert.pub" -replace "~", "$HOME" )
                break
            }
        }
    }

    if ( $null -eq $domain ) {
        # just do what was asked with no further checks
        & $cmdPath $args
        return
    }

    if ( $args -match "@sshenrol\.${domain}(\s|$)" ) {
        # enrolling so call ssh
        & $sshPath $args
        return
    }

    Set-Variable -Name renew -Value $true

    if ( Test-Path -Path "$cert" -PathType Leaf ) {
        $valid = $( & ssh-keygen -Lf $cert | select-string 'Valid:' ) -replace '^(.* to )(.*)', '$2'
        $until = [int64]( get-date -uformat %s $valid )
        if ( [int64]( get-date -uformat %s ) -lt $until ) {
            Write-Host "+faythe: Current signed certificate valid until $valid"
            $renew = $false
        }
        else {
            Write-Host "+faythe: Signed certificate expired $valid"
        }
    }

    if ( $renew ) {
        Write-Host "+faythe: Requesting signed certificate ..."
        $out = & $sshPath -T "${login}@sshca.${domain}"
        # select-string doesn't work properly on older powershell,
        # so use this instead
        $key = $( $out | Where-Object { $_ -match "^ssh-(rsa|ed25519|ecdsa)-cert-v\d+@openssh.com A" } )

        if ( $key ) {
            $key | Out-File -Encoding ascii -FilePath $cert
            $valid = $( & ssh-keygen -Lf $cert | Select-String Valid: ) -replace "^(.* to )(.)", "$2"
            Write-Host "+faythe: Wrote new key to $cert file - valid until $valid"
        }
        else {
            Write-Host "+faythe: Failed to update cert signed key."
            Write-Host $out
            return
        }
    }

    # run the command
    & $cmdPath $args

}

function fssh {
    _faythe -cmd "ssh"
}

function fscp {
    _faythe -cmd "scp"
}

# optional but recommended - override ssh and scp
Set-Alias -Name ssh -Value fssh
Set-Alias -Name scp -Value fscp