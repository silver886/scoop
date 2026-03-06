$ErrorActionPreference = 'Stop'

function Write-LogDebug   ($msg) { [Console]::Error.WriteLine("$(Get-Date -Format o) [DEBUG] $msg") }
function Write-LogInfo    ($msg) { [Console]::Error.WriteLine("$(Get-Date -Format o) [INFO] $msg") }
function Write-LogWarning ($msg) { [Console]::Error.WriteLine("$(Get-Date -Format o) [WARN] $msg") }
function Write-LogError   ($msg) { [Console]::Error.WriteLine("$(Get-Date -Format o) [ERROR] $msg") }

# Job Object: OS kills all assigned processes when the last handle closes.
# Kill chain: Task Scheduler kills conhost -> parent watcher detects death ->
# PowerShell exits -> Job Object handle closed -> wsl.exe killed ->
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
if ss -xl 2>/dev/null | grep -qF "$SOCKET"; then exit 5; fi
mkdir -p "$(dirname "$SOCKET")" || exit 4
rm -f "$SOCKET"
rm -f "$0"
socat \
  UNIX-LISTEN:"$SOCKET",fork,mode=600 \
  EXEC:"$WSPB_NPIPERELAY -ei -s $WSPB_PIPE",nofork &
SOCAT_PID=$!
echo $SOCAT_PID > "$PIDFILE"
trap 'kill $SOCAT_PID 2>/dev/null; rm -f "$SOCKET" "$PIDFILE"' EXIT
trap 'exit 0' TERM INT HUP
wait $SOCAT_PID
'@

Set-Variable -Name 'CleanupScript' -Option Constant -Value @'
S=$(eval echo "${WSL_SSH_PAGEANT_BRIDGE_SOCK:-}")
P="${S}.pid"
[ -f "$P" ] && kill -9 $(cat "$P") 2>/dev/null
rm -f "$S" "$P"
true
'@

$pipePattern = [regex]'^pageant\..+\.[0-9a-f]{64}$'
function Find-PageantPipe {
    foreach ($f in [IO.Directory]::GetFiles('\\.\pipe\', 'pageant.*')) {
        $name = $f.Substring('\\.\pipe\'.Length)
        if ($pipePattern.IsMatch($name)) { return $f }
    }
}

function Start-Wsl ($arguments) {
    $psi = [Diagnostics.ProcessStartInfo]::new('wsl', $arguments)
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

while ($true) {
    Write-LogInfo 'Waiting for WSL...'
    wsl --list --running 2>$null >$null
    while ($LASTEXITCODE -ne 0) {
        Assert-ParentAlive
        [Threading.Thread]::Sleep(5000)
        wsl --list --running 2>$null >$null
    }
    Write-LogInfo 'WSL is running'

    # Kill orphaned socat from previous runs using PID file (targets only our instance)
    Write-LogDebug 'Cleaning up orphaned socat...'
    $cleanup = Start-Wsl ('bash -c "' + ($CleanupScript -replace '"', '\"' -replace '\r?\n', '; ') + '"')
    $cleanup.WaitForExit(5000) >$null

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
    Write-LogDebug "Pageant pipe = $pipePath"

    $env:WSPB_PIPE = $pipePath.Replace('\', '/')

    $tmpScript = [IO.Path]::Combine($env:TEMP, [IO.Path]::GetRandomFileName() + '.sh')
    [IO.File]::WriteAllText($tmpScript, $BridgeScript)
    $env:WSPB_SCRIPT = $tmpScript

    Write-LogInfo 'Launching socat bridge...'
    $wslProc = Start-Wsl 'bash "$WSPB_SCRIPT"'
    $job.AssignProcess($wslProc.Handle)
    Write-LogDebug "wsl.exe PID $($wslProc.Id) assigned to Job Object"

    while (-not $wslProc.HasExited) {
        Assert-ParentAlive
        [Threading.Thread]::Sleep(500)
    }
    $exitCode = $wslProc.ExitCode

    if ($exitCode -in 2, 3, 4, 5) {
        Write-LogError "bash exited with config error ($exitCode)"
        exit $exitCode
    }
    Write-LogWarning "socat exited ($exitCode), restarting..."
}
