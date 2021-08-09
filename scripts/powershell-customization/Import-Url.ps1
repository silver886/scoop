function Import-Url () {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$src
    )

    if (-not ($src -match "^(?:(?<scheme>[A-Za-z][0-9A-Za-z+\-.]*?):)?\/\/(?:(?<user>(?:[0-9A-Za-z\-._~!$&'()*+,;=]|%[0-9A-Fa-f]{2})*?)(?::(?<pass>(?:[0-9A-Za-z\-._~!$&'()*+,;=]|%[0-9A-Fa-f]{2})*?))?@)?(?<host>[0-9A-Za-z%$\-_.+!*'(),]*?)(?::(?<port>[0-9A-Za-z%$\-_.+!*'(),]*?))?(?:(?<path>\/(?:[0-9A-Za-z\/\-._~!$&'()*+,;=:@]|%[0-9A-Fa-f]{2})*?))?(?:\?(?<query>(?:[0-9A-Za-z\/\-._~!?$&'()*+,;=:@]|%[0-9A-Fa-f]{2})*?))?(?:#(?<fragment>(?:[0-9A-Za-z\/\-._~!?$&'()*+,;=:@]|%[0-9A-Fa-f]{2})*?))?$")) {
        Write-Error -Message 'Not able to parse URL' -ErrorAction Stop
    }

    return [PSCustomObject]@{
        Scheme   = $Matches.Scheme
        User     = $Matches.User
        Pass     = $Matches.Pass
        Host     = $Matches.Host
        Port     = $Matches.Port
        Path     = $Matches.Path
        Query    = $Matches.Query
        Fragment = $Matches.Fragment
    }
}
