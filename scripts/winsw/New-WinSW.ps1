[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Name
)

begin {
    $ServiceDirectory = "$dir\services\$Name"

    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error -Message 'This action must be executed as Administrator.' -ErrorAction Stop
    }
    if (Test-Path -Path $ServiceDirectory -PathType Container) {
        Write-Error -Message "$Name already exists." -ErrorAction Stop
    }
}

process {
    New-Item -Path $ServiceDirectory -ItemType Directory > $null
    New-Item -Path "$ServiceDirectory\winsw.exe" -ItemType SymbolicLink -Value "$dir\winsw.exe" > $null
    Copy-Item -Path "$dir\winsw-template.xml" -Destination "$ServiceDirectory\winsw.xml" > $null
}
