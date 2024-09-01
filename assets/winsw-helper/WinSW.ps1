#Requires -RunAsAdministrator

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateSet('create', 'destroy')]
    [string]$Action,

    [Parameter(Mandatory)]
    [string]$Name,

    [switch]$Force
)

$WinswExe = "$scoopdir\apps\winsw\current\winsw.exe"
$Services = "$dir\services"
$TemplateXml = "$dir\winsw-template.xml"
$CurrentServiceDirectory = "$Services\$Name"
$CurrentServiceWinswExe = "$CurrentServiceDirectory\winsw.exe"
$CurrentServiceWinswXml = "$CurrentServiceDirectory\winsw.xml"
$CurrentServiceShimExe = "$Services\winsw-service-$Name.exe"
$CurrentServiceShimConfig = "$Services\winsw-service-$Name.shim"
$ShimExe = "$scoopdir\apps\scoop\current\supporting\shims\kiennq\shim.exe"

switch ($Action) {
    'create' {
        if (-not $Force -and ((Test-Path -Path $CurrentServiceDirectory -PathType Container) -or (Test-Path -Path $CurrentServiceShimExe -PathType Leaf) -or (Test-Path -Path $CurrentServiceShimConfig -PathType Leaf))) {
            Write-Error -Message "Service '$Name' already exists." -ErrorAction Stop
        }
    }
    'destroy' {
        if (-not ($Force -or (Test-Path -Path $CurrentServiceDirectory -PathType Container))) {
            Write-Error -Message "Service '$Name' does not exist." -ErrorAction Stop
        }
    }
}

switch ($Action) {
    'create' {
        New-Item -Force -Path $CurrentServiceDirectory -ItemType Directory -ErrorAction Stop > $null
        New-Item -Force -Path $CurrentServiceWinswExe -ItemType SymbolicLink -Value $WinswExe -ErrorAction Stop > $null
        Copy-Item -Force -Path $TemplateXml -Destination $CurrentServiceWinswXml -ErrorAction Stop > $null
        Copy-Item -Force -Path $ShimExe -Destination $CurrentServiceShimExe -ErrorAction Stop > $null
        Set-Content -Force -Path $CurrentServiceShimConfig -Value "path = $CurrentServiceWinswExe" -Encoding Ascii -ErrorAction Stop > $null
    }
    'destroy' {
        Write-Output "Service '$Name' stopping"
        & $CurrentServiceWinswExe stopwait
        Write-Output "Service '$Name' stopped"
        Write-Output "Service '$Name' uninstalling"
        & $CurrentServiceWinswExe uninstall
        Write-Output "Service '$Name' uninstalled"
        Remove-Item -Force -Recurse -Path $CurrentServiceDirectory, $CurrentServiceShimExe, $CurrentServiceShimConfig -ErrorAction SilentlyContinue > $null
    }
}

switch ($Action) {
    'create' {
        Write-Output "Service '$Name' created"
        Write-Output "Config file located at '$CurrentServiceWinswXml'"
    }
    'destroy' {
        Write-Output "Service '$Name' destroyed"
    }
}
