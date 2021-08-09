[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateSet('create', 'destroy', 'install', 'uninstall', 'reinstall', 'start', 'stop', 'stopwait', 'restart', 'restart!', 'status', 'test', 'testwait', 'version', 'help')]
    [string]$Action,

    [Parameter(Mandatory)]
    [string]$Name
)

begin {
    $ServiceDirectory = "$dir\services\$Name"

    function CheckService {
        if (-not (Test-Path -Path $ServiceDirectory -PathType Container)) {
            Write-Error -Message "Service '$Name' does not exist." -ErrorAction Stop
        }
    }

    if ($Action -eq 'create') {
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Error -Message 'This action must be executed as Administrator.' -ErrorAction Stop
        }
        if (Test-Path -Path $ServiceDirectory -PathType Container) {
            Write-Error -Message "Service '$Name' already exists." -ErrorAction Stop
        }
    }
    else {
        CheckService
    }
}

process {
    switch ($Action) {
        'create' {
            New-Item -Path $ServiceDirectory -ItemType Directory > $null
            New-Item -Path "$ServiceDirectory\winsw.exe" -ItemType SymbolicLink -Value "$dir\winsw.exe" > $null
            Copy-Item -Path "$dir\winsw-template.xml" -Destination "$ServiceDirectory\winsw.xml" > $null

        }
        'destroy' {
            . "$ServiceDirectory\winsw.exe" stopwait
            . "$ServiceDirectory\winsw.exe" uninstall
            Remove-Item -Force -Recurse -Path $ServiceDirectory
        }
        'install' {
            . "$ServiceDirectory\winsw.exe" install
        }
        'uninstall' {
            . "$ServiceDirectory\winsw.exe" uninstall
        }
        'reinstall' {
            . "$ServiceDirectory\winsw.exe" uninstall
            . "$ServiceDirectory\winsw.exe" install
        }
        'start' {
            . "$ServiceDirectory\winsw.exe" start
        }
        'stop' {
            . "$ServiceDirectory\winsw.exe" stop
        }
        'stopwait' {
            . "$ServiceDirectory\winsw.exe" stopwait
        }
        'restart' {
            . "$ServiceDirectory\winsw.exe" restart
        }
        'restart!' {
            . "$ServiceDirectory\winsw.exe" restart!
        }
        'status' {
            . "$ServiceDirectory\winsw.exe" status
        }
        'test' {
            . "$ServiceDirectory\winsw.exe" test
        }
        'testwait' {
            . "$ServiceDirectory\winsw.exe" testwait
        }
        'version' {
            . "$ServiceDirectory\winsw.exe" version
        }
        'help' {
            . "$ServiceDirectory\winsw.exe" help
        }
    }
}

end {
    switch ($Action) {
        'create' {
            Write-Output "Service '$Name' created"
        }
        'destroy' {
            Write-Output "Service '$Name' destroyed"
        }
    }
}
