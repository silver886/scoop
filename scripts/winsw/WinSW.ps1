[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateSet('create', 'destroy', 'test', 'status', 'install', 'uninstall', 'reinstall', 'start', 'stop', 'restart')]
    [string]$Action,

    [Parameter(Mandatory)]
    [string]$Name
)

begin {
    $ServiceDirectory = "$dir\services\$Name"

    switch ($Action) {
        'create' {
            if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                Write-Error -Message 'This action must be executed as Administrator.' -ErrorAction Stop
            }
            if (Test-Path -Path $ServiceDirectory -PathType Container) {
                Write-Error -Message "$Name already exists." -ErrorAction Stop
            }
        }
        'destroy' {
            if (-not (Test-Path -Path $ServiceDirectory -PathType Container)) {
                Write-Error -Message "$Name does not exist." -ErrorAction Stop
            }
        }
        'test' {}
        'status' {}
        'install' {}
        'uninstall' {}
        'reinstall' {}
        'start' {}
        'stop' {}
        'restart' {}
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
            Remove-Item -Force -Recurse -Path $ServiceDirectory
        }
        'test' {}
        'status' {}
        'install' {}
        'uninstall' {}
        'reinstall' {}
        'start' {}
        'stop' {}
        'restart' {}
    }
}

end {
    switch ($Action) {
        'create' {
            Write-Output "$Name created"
        }
        'destroy' {
            Write-Output "$Name destroyed"
        }
        'test' {}
        'status' {}
        'install' {}
        'uninstall' {}
        'reinstall' {}
        'start' {}
        'stop' {}
        'restart' {}
    }
}
