$ErrorActionPreference = "Stop"

$AppDir = $PSScriptRoot
$BinDir = Join-Path $AppDir "bin"
$ConfigPath = Join-Path $AppDir "config.json"

# --- Helpers ---

function Import-Config {
    if (Test-Path $ConfigPath) {
        return Get-Content $ConfigPath -Raw | ConvertFrom-Json
    }
    return [PSCustomObject]@{ aliases = @() }
}

function Export-Config($cfg) {
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
}

function Test-SafeName($value) {
    return $value -match '^\w[\w\-\.]*$' -and $value -notmatch '\.\.'
}

function Write-Shim($name, $distro) {
    if (!(Test-SafeName $name)) { Write-Host "Invalid name: $name" -ForegroundColor Red; return $false }
    if ($distro -and !(Test-SafeName $distro)) { Write-Host "Invalid distro: $distro" -ForegroundColor Red; return $false }
    if (!(Test-Path $BinDir)) { New-Item -ItemType Directory $BinDir -Force | Out-Null }
    $path = Join-Path $BinDir "$name.cmd"
    if ($distro) {
        $body = "@echo off`r`nwsl.exe -d $distro $name %*`r`nexit /b %ERRORLEVEL%"
    }
    else {
        $body = "@echo off`r`nwsl.exe $name %*`r`nexit /b %ERRORLEVEL%"
    }
    [IO.File]::WriteAllText($path, $body)
    return $true
}

# --- Subcommands ---

function Add-Shim($params) {
    $names = @(); $distro = $null; $force = $false
    for ($i = 0; $i -lt $params.Count; $i++) {
        if ($params[$i] -in @("--distro", "-d")) {
            if (++$i -ge $params.Count) { Write-Host "Error: --distro requires a value" -ForegroundColor Red; return }
            $distro = $params[$i]
        }
        elseif ($params[$i] -in @("--force", "-f")) { $force = $true }
        else { $names += $params[$i] }
    }
    if (!$names) { Write-Host "Usage: wsl-shim add <name>... [-d <distro>] [-f]"; return }

    $cfg = Import-Config
    $list = [Collections.ArrayList]@($cfg.aliases)

    foreach ($n in $names) {
        $existing = $list | Where-Object name -eq $n | Select-Object -First 1
        if ($existing -and !$force) {
            Write-Host "  ~ $n exists (use -f to overwrite)" -ForegroundColor Yellow
            continue
        }

        if (!(Write-Shim $n $distro)) { continue }

        if ($existing) { $list.Remove($existing) | Out-Null }

        $list.Add([PSCustomObject]@{
                name    = $n
                distro  = $(if ($distro) { $distro } else { "" })
                created = (Get-Date -Format yyyy-MM-dd)
            }) | Out-Null

        $msg = "  + $n"
        if ($distro) { $msg += "  ($distro)" }
        Write-Host $msg -ForegroundColor Green
    }

    $cfg.aliases = @($list)
    Export-Config $cfg
}

function Remove-Shim($params) {
    $all = $false; $names = @()
    foreach ($p in $params) {
        if ($p -eq "--all") { $all = $true } else { $names += $p }
    }

    $cfg = Import-Config
    $list = [Collections.ArrayList]@($cfg.aliases)
    if ($all) { $names = @($list | ForEach-Object name) }
    if (!$names) { Write-Host "Usage: wsl-shim rm <name>... [--all]"; return }

    foreach ($n in $names) {
        if (!(Test-SafeName $n)) { Write-Host "Invalid name: $n" -ForegroundColor Red; continue }
        $shim = Join-Path $BinDir "$n.cmd"
        if (Test-Path $shim) { Remove-Item $shim }
        $entry = $list | Where-Object name -eq $n | Select-Object -First 1
        if ($entry) {
            $list.Remove($entry) | Out-Null
            Write-Host "  - $n" -ForegroundColor Red
        }
        else {
            Write-Host "  ? $n not found" -ForegroundColor Yellow
        }
    }

    $cfg.aliases = @($list)
    Export-Config $cfg
}

function Show-ShimList {
    $cfg = Import-Config
    if (!$cfg.aliases -or $cfg.aliases.Count -eq 0) {
        Write-Host "No aliases. Use 'wsl-shim add <name>' to create one."
        return
    }
    $cfg.aliases | ForEach-Object {
        [PSCustomObject]@{
            Name    = $_.name
            Distro  = $(if ($_.distro) { $_.distro } else { "(wsl default)" })
            Created = $_.created
        }
    } | Format-Table -AutoSize
}

function Show-Help {
    @"

wsl-shim - expose WSL binaries as Windows commands

USAGE
    wsl-shim add <name>... [-d|--distro <distro>] [-f|--force]
    wsl-shim rm  <name>... [--all]
    wsl-shim list

EXAMPLES
    wsl-shim add ssh curl git rsync
    wsl-shim add nmap -d Kali
    wsl-shim add ssh -d Debian -f
    wsl-shim list
    wsl-shim rm curl
    wsl-shim rm --all

"@ | Write-Host
}

# --- Entry ---

$cmd = if ($args.Count -gt 0) { $args[0] } else { "" }
$rest = if ($args.Count -gt 1) { , @($args[1..($args.Count - 1)]) } else { @() }

switch ($cmd) {
    "add" { Add-Shim $rest }
    "rm" { Remove-Shim $rest }
    "remove" { Remove-Shim $rest }
    "list" { Show-ShimList }
    "ls" { Show-ShimList }
    default { Show-Help }
}
