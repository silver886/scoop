param(
    [string]$Paths = "C:\users\ll\fork;C:\users\ll\greenhouse",
    [int]$MaxDepth = [int]::MaxValue
)

$psi = [System.Diagnostics.ProcessStartInfo]::new('fzf')
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.UseShellExecute = $false
$fzf = [System.Diagnostics.Process]::Start($psi)

$roots = $Paths.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
$queue = [System.Collections.Generic.List[string[]]]::new()
$queue.Add([string[]]($roots | ForEach-Object { [System.IO.Path]::GetFullPath($_) }))

:outer for ($d = 0; $d -lt $MaxDepth; $d++) {
    if ($queue[$d].Length -eq 0) { break }
    $next = [System.Collections.Generic.List[string]]::new()
    foreach ($dir in $queue[$d]) {
        if ($fzf.HasExited) { break outer }
        try {
            $children = [System.IO.Directory]::GetDirectories($dir)
        }
        catch {
            continue
        }
        foreach ($child in $children) {
            if ([System.IO.Path]::GetFileName($child) -eq '.git') {
                try { $fzf.StandardInput.WriteLine($dir) } catch { break outer }
            }
            else {
                $next.Add($child)
            }
        }
    }
    $queue.Add($next.ToArray())
}

try { $fzf.StandardInput.Close() } catch {}
$result = $fzf.StandardOutput.ReadToEnd().Trim()
$fzf.WaitForExit()
if ($result) { lazygit --path $result }
