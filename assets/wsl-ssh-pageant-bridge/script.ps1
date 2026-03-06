$ErrorActionPreference = 'Stop'

function Write-LogDebug   ($msg) { [Console]::Error.WriteLine("$(Get-Date -Format o) [DEBUG] $msg") }
function Write-LogInfo    ($msg) { [Console]::Error.WriteLine("$(Get-Date -Format o) [INFO] $msg") }
function Write-LogWarning ($msg) { [Console]::Error.WriteLine("$(Get-Date -Format o) [WARN] $msg") }
function Write-LogError   ($msg) { [Console]::Error.WriteLine("$(Get-Date -Format o) [ERROR] $msg") }

$npiperelayWin = (Get-Command 'npiperelay' -ErrorAction SilentlyContinue).Source
if (-not $npiperelayWin) {
    Write-LogError 'npiperelay not found in PATH'
    exit 1
}
Write-LogDebug "npiperelay = $npiperelayWin"
$env:WSPB_NPIPERELAY = $npiperelayWin

$wslenvParts = 'WSPB_NPIPERELAY/up:WSPB_PIPE/u:WSPB_SCRIPT/up'
if ($env:WSLENV) {
    $env:WSLENV = "$env:WSLENV`:$wslenvParts"
}
else {
    $env:WSLENV = $wslenvParts
}
Write-LogDebug "WSLENV = $env:WSLENV"

$bashScript = @'
#!/bin/bash
set -euo pipefail
if [ -z "${WSL_SSH_PAGEANT_BRIDGE_SOCK:-}" ]; then echo "WSL_SSH_PAGEANT_BRIDGE_SOCK not set" >&2; exit 2; fi
SOCKET=$(eval echo "$WSL_SSH_PAGEANT_BRIDGE_SOCK")
case "$SOCKET" in /*) ;; *) echo "invalid socket path: $SOCKET" >&2; exit 3;; esac
if ss -xl 2>/dev/null | grep -qF "$SOCKET"; then exit 5; fi
mkdir -p "$(dirname "$SOCKET")" || exit 4
rm -f "$SOCKET"
rm -f "$0"
exec socat \
  UNIX-LISTEN:"$SOCKET",fork,mode=600 \
  EXEC:"$WSPB_NPIPERELAY -ei -s $WSPB_PIPE",nofork
'@

$pipePattern = [regex]'^pageant\..+\.[0-9a-f]{64}$'
function Find-PageantPipe {
    foreach ($f in [IO.Directory]::GetFiles('\\.\pipe\', 'pageant.*')) {
        $name = $f.Substring('\\.\pipe\'.Length)
        if ($pipePattern.IsMatch($name)) { return $f }
    }
}

while ($true) {
    Write-LogInfo 'Waiting for WSL...'
    wsl --list --running 2>$null >$null
    while ($LASTEXITCODE -ne 0) {
        [Threading.Thread]::Sleep(5000)
        wsl --list --running 2>$null >$null
    }
    Write-LogInfo 'WSL is running'

    $pipePath = Find-PageantPipe
    if (-not $pipePath) {
        Write-LogWarning 'Pageant pipe not found, starting pageant...'
        Start-Process 'pageant'
        for ($i = 0; $i -lt 40; $i++) {
            [Threading.Thread]::Sleep(250)
            $pipePath = Find-PageantPipe
            if ($pipePath) { break }
        }
    }
    if (-not $pipePath) {
        Write-LogWarning 'Pageant pipe not found after waiting, retrying...'
        [Threading.Thread]::Sleep(5000)
        continue
    }
    Write-LogDebug "Pageant pipe = $pipePath"

    $env:WSPB_PIPE = $pipePath.Replace('\', '/')

    $tmpScript = [IO.Path]::Combine($env:TEMP, [IO.Path]::GetRandomFileName() + '.sh')
    [IO.File]::WriteAllText($tmpScript, $bashScript)
    $env:WSPB_SCRIPT = $tmpScript

    Write-LogInfo 'Launching socat bridge...'
    $p = Start-Process -FilePath 'wsl' -ArgumentList 'bash', '"$WSPB_SCRIPT"' `
        -WindowStyle Hidden -Wait -PassThru

    if ($p.ExitCode -in 2, 3, 4, 5) {
        Write-LogError "bash exited with config error ($($p.ExitCode))"
        exit $p.ExitCode
    }
    Write-LogWarning "socat exited ($($p.ExitCode)), restarting..."
}
