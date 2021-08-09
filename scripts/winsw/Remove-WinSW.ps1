[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Name
)

begin {
    $ServiceDirectory = "$dir\services\$Name"

    if (-not (Test-Path -Path $ServiceDirectory -PathType Container)) {
        Write-Error -Message "$Name does not exist." -ErrorAction Stop
    }
}

process {
    Remove-Item -Force -Recurse -Path $ServiceDirectory
}
