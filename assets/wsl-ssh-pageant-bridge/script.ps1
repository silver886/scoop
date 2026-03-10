$ErrorActionPreference = 'Stop'

if (-not [Environment]::Is64BitProcess) {
    $env:PATH = "$env:SystemRoot\Sysnative;$env:PATH"
}

function Write-LogDebug   ($msg) { [Console]::Error.WriteLine("$(Get-Date -Format o) [DEBUG] $msg") }
function Write-LogInfo    ($msg) { [Console]::Error.WriteLine("$(Get-Date -Format o) [INFO] $msg") }
function Write-LogWarning ($msg) { [Console]::Error.WriteLine("$(Get-Date -Format o) [WARN] $msg") }
function Write-LogError   ($msg) { [Console]::Error.WriteLine("$(Get-Date -Format o) [ERROR] $msg") }

# Job Object: OS kills all assigned processes when the last handle closes.
# Kill chain: Task Scheduler kills conhost -> parent watcher detects death ->
# PowerShell exits -> Job Object handle closed -> all wsl.exe killed ->
# bash receives SIGHUP -> trap kills socat + removes socket.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class JobObject : IDisposable {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr hJob, int infoClass, IntPtr lpInfo, uint cbSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public long PerProcessUserTimeLimit;    // 8
        public long PerJobUserTimeLimit;        // 8
        public uint LimitFlags;                 // 4 (+4 padding)
        public UIntPtr MinimumWorkingSetSize;   // 8
        public UIntPtr MaximumWorkingSetSize;   // 8
        public uint ActiveProcessLimit;         // 4 (+4 padding)
        public UIntPtr Affinity;                // 8
        public uint PriorityClass;              // 4
        public uint SchedulingClass;            // 4
    }

    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    IntPtr _handle;

    public JobObject() {
        _handle = CreateJobObject(IntPtr.Zero, null);
        if (_handle == IntPtr.Zero) {
            throw new Exception("CreateJobObject failed: " + Marshal.GetLastWin32Error());
        }

        var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        info.BasicLimitInformation.LimitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE

        int size = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
        IntPtr ptr = Marshal.AllocHGlobal(size);
        try {
            Marshal.StructureToPtr(info, ptr, false);
            // 9 = JobObjectExtendedLimitInformation
            if (!SetInformationJobObject(_handle, 9, ptr, (uint)size)) {
                throw new Exception("SetInformationJobObject failed: " + Marshal.GetLastWin32Error());
            }
        } finally {
            Marshal.FreeHGlobal(ptr);
        }
    }

    public void AssignProcess(IntPtr processHandle) {
        if (!AssignProcessToJobObject(_handle, processHandle)) {
            throw new Exception("AssignProcessToJobObject failed: " + Marshal.GetLastWin32Error());
        }
    }

    public void Dispose() {
        if (_handle != IntPtr.Zero) {
            CloseHandle(_handle);
            _handle = IntPtr.Zero;
        }
    }
}
'@

$job = [JobObject]::new()
Write-LogDebug "Job Object created (KILL_ON_JOB_CLOSE)"

$parentProc = [Diagnostics.Process]::GetProcessById(
    (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
)
Write-LogDebug "Parent process = $($parentProc.ProcessName) (PID $($parentProc.Id))"

function Find-InPath ($name) {
    foreach ($dir in $env:PATH.Split(';')) {
        if ($dir) {
            $candidate = [IO.Path]::Combine($dir, "$name.exe")
            if ([IO.File]::Exists($candidate)) { return $candidate }
        }
    }
}

$npiperelayWin = Find-InPath 'npiperelay'
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

Set-Variable -Name 'BridgeScript' -Option Constant -Value @'
#!/bin/bash
set -euo pipefail
if [ -z "${WSL_SSH_PAGEANT_BRIDGE_SOCK:-}" ]; then echo "WSL_SSH_PAGEANT_BRIDGE_SOCK not set" >&2; exit 2; fi
SOCKET=$(eval echo "$WSL_SSH_PAGEANT_BRIDGE_SOCK")
case "$SOCKET" in /*) ;; *) echo "invalid socket path: $SOCKET" >&2; exit 3;; esac
PIDFILE="${SOCKET}.pid"
mkdir -p "$(dirname "$SOCKET")" || exit 4
# Kill orphaned socat from previous run (uses only /proc — works on all distros)
kill_socat() {
  kill "$1" 2>/dev/null || return 0
  for _i in 1 2 3 4 5; do [ -d "/proc/$1" ] || return 0; sleep 0.1; done
  kill -9 "$1" 2>/dev/null || true
}
# Fast path: use PID file if valid
KILLED=false
if [ -f "$PIDFILE" ]; then
  OLD_PID=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$OLD_PID" ] && grep -qx socat "/proc/$OLD_PID/comm" 2>/dev/null \
     && tr '\0' '\n' < "/proc/$OLD_PID/cmdline" 2>/dev/null | grep -qF "$SOCKET"; then
    kill_socat "$OLD_PID"
    KILLED=true
  fi
  rm -f "$PIDFILE"
fi
# Slow path: PID file missing/invalid but socket exists — scan /proc for orphaned socat
if [ "$KILLED" = false ] && [ -S "$SOCKET" ]; then
  for p in /proc/[0-9]*/comm; do
    [ -f "$p" ] || continue
    grep -qx socat "$p" 2>/dev/null || continue
    pid="${p#/proc/}"; pid="${pid%/comm}"
    tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | grep -qF "$SOCKET" || continue
    kill_socat "$pid"
  done
fi
rm -f "$SOCKET"
rm -f "$0"
socat \
  UNIX-LISTEN:"$SOCKET",fork,mode=600 \
  EXEC:"$WSPB_NPIPERELAY -ei -s $WSPB_PIPE",nofork &
SOCAT_PID=$!
echo "$SOCAT_PID" > "$PIDFILE"
cleanup() {
  kill "$SOCAT_PID" 2>/dev/null
  if [ "$(cat "$PIDFILE" 2>/dev/null)" = "$SOCAT_PID" ]; then
    rm -f "$SOCKET" "$PIDFILE"
  fi
}
trap cleanup EXIT
trap 'exit 0' TERM INT HUP
# Monitor socat AND pidfile: exit if socat dies, pidfile removed, or pidfile changed
while kill -0 "$SOCAT_PID" 2>/dev/null; do
  if [ ! -f "$PIDFILE" ] || [ "$(cat "$PIDFILE" 2>/dev/null)" != "$SOCAT_PID" ]; then
    break
  fi
  sleep 1
done
'@

$pipePattern = [regex]'^pageant\..+\.[0-9a-f]{64}$'
function Find-PageantPipe {
    foreach ($f in [IO.Directory]::GetFiles('\\.\pipe\', 'pageant.*')) {
        $name = $f.Substring('\\.\pipe\'.Length)
        if ($pipePattern.IsMatch($name)) { return $f }
    }
}

function Start-Wsl ($distro, $arguments) {
    $psi = [Diagnostics.ProcessStartInfo]::new('wsl', "-d $distro $arguments")
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    return [Diagnostics.Process]::Start($psi)
}

function Assert-ParentAlive {
    if ($parentProc.HasExited) {
        Write-LogWarning 'Parent process died, exiting (Job Object will clean up)...'
        [Environment]::Exit(0)
    }
}

function Get-RunningDistros {
    $output = wsl --list --running --quiet 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    @($output | ForEach-Object { ($_ -replace '\x00', '').Trim() } | Where-Object { $_ })
}

$bridges = @{}
$failed = [Collections.Generic.HashSet[string]]::new()

while ($true) {
    Assert-ParentAlive

    $distros = Get-RunningDistros
    if ($distros.Count -eq 0) {
        Write-LogInfo 'No WSL instances running, waiting...'
        [Threading.Thread]::Sleep(5000)
        continue
    }

    # Clear tracking for distros that stopped (allows retry when they restart)
    foreach ($name in @($bridges.Keys)) {
        if ($name -notin $distros) {
            Write-LogInfo "[$name] Distro stopped"
            $bridges.Remove($name)
        }
    }
    foreach ($name in @($failed)) {
        if ($name -notin $distros) {
            $failed.Remove($name) | Out-Null
        }
    }

    # Find pageant pipe (shared across all distros)
    $pipePath = Find-PageantPipe
    if (-not $pipePath) {
        Write-LogWarning 'Pageant pipe not found, starting pageant...'
        [Diagnostics.Process]::Start('pageant')
        for ($i = 0; $i -lt 40; $i++) {
            Assert-ParentAlive
            [Threading.Thread]::Sleep(250)
            $pipePath = Find-PageantPipe
            if ($pipePath) { break }
        }
    }
    if (-not $pipePath) {
        Write-LogWarning 'Pageant pipe not found after waiting, retrying...'
        Assert-ParentAlive
        [Threading.Thread]::Sleep(5000)
        continue
    }
    $env:WSPB_PIPE = $pipePath.Replace('\', '/')

    foreach ($distro in $distros) {
        if ($failed.Contains($distro)) { continue }

        # Check existing bridge
        if ($bridges.ContainsKey($distro)) {
            if (-not $bridges[$distro].HasExited) { continue }

            $exitCode = $bridges[$distro].ExitCode
            $bridges.Remove($distro)

            if ($exitCode -in 2, 3, 4) {
                Write-LogError "[$distro] bash exited with config error ($exitCode)"
                $failed.Add($distro) | Out-Null
                continue
            }
            Write-LogWarning "[$distro] socat exited ($exitCode), restarting..."
        }

        # Write temp script and launch bridge
        $tmpScript = [IO.Path]::Combine($env:TEMP, [IO.Path]::GetRandomFileName() + '.sh')
        [IO.File]::WriteAllText($tmpScript, $BridgeScript.Replace("`r`n", "`n"))
        $env:WSPB_SCRIPT = $tmpScript

        Write-LogInfo "[$distro] Launching socat bridge..."
        $wslProc = Start-Wsl $distro 'bash "$WSPB_SCRIPT"'
        $job.AssignProcess($wslProc.Handle)
        Write-LogDebug "[$distro] wsl.exe PID $($wslProc.Id) assigned to Job Object"

        $bridges[$distro] = $wslProc
    }

    [Threading.Thread]::Sleep(1000)
}


Stop-Transcript
