$ErrorActionPreference = "Stop"

$AppDir = $PSScriptRoot
$BinDir = Join-Path $AppDir "bin"
$ConfigPath = Join-Path $AppDir "config.json"

# --- Helpers ---

function Import-Config {
    if (Test-Path $ConfigPath) {
        return Get-Content $ConfigPath -Raw | ConvertFrom-Json
    }
    return [PSCustomObject]@{ default_distro = ""; aliases = @() }
}

function Export-Config($cfg) {
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
}

function Write-Shim($name, $distro) {
    if (!(Test-Path $BinDir)) { New-Item -ItemType Directory $BinDir -Force | Out-Null }
    $path = Join-Path $BinDir "$name.cmd"
    if ($distro) {
        $body = "@echo off`r`nwsl.exe -d $distro $name %*`r`nexit /b %ERRORLEVEL%"
    }
    else {
        $body = "@echo off`r`nwsl.exe $name %*`r`nexit /b %ERRORLEVEL%"
    }
    [IO.File]::WriteAllText($path, $body)
}

# --- Subcommands ---

function Do-Add($params) {
    $names = @(); $distro = $null; $force = $false
    for ($i = 0; $i -lt $params.Count; $i++) {
        if ($params[$i] -in @("--distro", "-d")) { $distro = $params[++$i] }
        elseif ($params[$i] -in @("--force", "-f")) { $force = $true }
        else { $names += $params[$i] }
    }
    if (!$names) { Write-Host "Usage: wsl-shim add <name>... [-d <distro>] [-f]"; exit 1 }

    $cfg = Import-Config
    $list = [Collections.ArrayList]@($cfg.aliases)

    foreach ($n in $names) {
        $existing = $list | Where-Object name -eq $n
        if ($existing -and !$force) {
            Write-Host "  ~ $n exists (use -f to overwrite)" -ForegroundColor Yellow
            continue
        }
        if ($existing) { $list.Remove($existing) | Out-Null }

        $eff = if ($distro) { $distro } else { $cfg.default_distro }
        Write-Shim $n $eff

        $list.Add([PSCustomObject]@{
                name    = $n
                distro  = $(if ($distro) { $distro } else { "" })
                created = (Get-Date -Format yyyy-MM-dd)
            }) | Out-Null

        $msg = "  + $n"
        if ($eff) { $msg += "  ($eff)" }
        Write-Host $msg -ForegroundColor Green
    }

    $cfg.aliases = @($list)
    Export-Config $cfg
}

function Do-Rm($params) {
    $all = $false; $names = @()
    foreach ($p in $params) {
        if ($p -eq "--all") { $all = $true } else { $names += $p }
    }

    $cfg = Import-Config
    $list = [Collections.ArrayList]@($cfg.aliases)
    if ($all) { $names = @($list | ForEach-Object name) }
    if (!$names) { Write-Host "Usage: wsl-shim rm <name>... [--all]"; exit 1 }

    foreach ($n in $names) {
        $shim = Join-Path $BinDir "$n.cmd"
        if (Test-Path $shim) { Remove-Item $shim }
        $entry = $list | Where-Object name -eq $n
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

function Do-List {
    $cfg = Import-Config
    if (!$cfg.aliases -or $cfg.aliases.Count -eq 0) {
        Write-Host "No aliases. Use 'wsl-shim add <name>' to create one."
        return
    }
    Write-Host ""
    Write-Host ("  {0,-14} {1,-18} {2}" -f "NAME", "DISTRO", "CREATED") -ForegroundColor Cyan
    Write-Host ("  {0,-14} {1,-18} {2}" -f "----", "------", "-------")
    foreach ($a in $cfg.aliases) {
        $d = if ($a.distro) { $a.distro }
        elseif ($cfg.default_distro) { "$($cfg.default_distro) *" }
        else { "(wsl default)" }
        Write-Host ("  {0,-14} {1,-18} {2}" -f $a.name, $d, $a.created)
    }
    Write-Host ""
}

function Do-Config($params) {
    $cfg = Import-Config
    if (!$params -or $params.Count -eq 0) {
        Write-Host ""
        Write-Host "  distro:  $(if ($cfg.default_distro) { $cfg.default_distro } else { '(wsl default)' })"
        Write-Host "  aliases: $($cfg.aliases.Count)"
        Write-Host "  bin:     $BinDir"
        Write-Host ""
        return
    }
    for ($i = 0; $i -lt $params.Count; $i++) {
        if ($params[$i] -in @("--distro", "-d")) {
            $cfg.default_distro = $params[++$i]
            if ($cfg.default_distro) {
                Write-Host "Default distro: $($cfg.default_distro)" -ForegroundColor Green
            }
            else {
                Write-Host "Default distro cleared" -ForegroundColor Green
            }
        }
    }
    Export-Config $cfg
}

function Show-Help {
    @"

wsl-shim - expose WSL binaries as Windows commands

USAGE
    wsl-shim add <name>... [-d|--distro <distro>] [-f|--force]
    wsl-shim rm  <name>... [--all]
    wsl-shim list
    wsl-shim config [-d|--distro <distro>]

EXAMPLES
    wsl-shim config -d Ubuntu
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
    "add" { Do-Add $rest }
    "rm" { Do-Rm $rest }
    "remove" { Do-Rm $rest }
    "list" { Do-List }
    "ls" { Do-List }
    "config" { Do-Config $rest }
    default { Show-Help }
}
