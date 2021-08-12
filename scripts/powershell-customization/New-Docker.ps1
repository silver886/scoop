function New-Docker {

    [CmdletBinding()]
    param (
        [switch]$DryRun,

        [string]$Image = 'alpine',

        [string[]]$Command,

        [string]$Entrypoint,

        [string[]]$Env,

        [string]$Name,

        [switch]$Remove,

        [switch]$Background,

        [string[]]$Volume,

        # [Parameter(Mandatory = $false, ParameterSetName = "Built-in")]
        [string]$WorkDir,

        [switch]$Docker,

        [string[]]$HostDir,

        # [Parameter(Mandatory = $false, ParameterSetName = "Customized")]
        [string]$HostWorkDir
    )

    $dockerArgs = @(
        '--interactive',
        '--tty'
    )

    if ($Env.Length -gt 0) {
        $Env.ForEach(
            {
                $dockerArgs += @('--env', $_)
            }
        )
    }
    if (-not $Name -eq '') {
        $dockerArgs += @('--name', $Name)
    }
    if (-not $Entrypoint -eq '') {
        $dockerArgs += @('--entrypoint', $Entrypoint)
    }
    if ($Remove) {
        $dockerArgs += @('--rm')
    }
    if ($Background) {
        $dockerArgs += @('--detach')
    }
    if ($Volume.Length -gt 0) {
        $Volume.ForEach(
            {
                $dockerArgs += @('--volume', $_)
            }
        )
    }
    if (-not $WorkDir -eq '') {
        $dockerArgs += @('--workdir', $WorkDir)
    }
    if ($Docker) {
        $dockerArgs += @('--volume', '/var/run/docker.sock:/var/run/docker.sock:rw')
    }
    if (-not $HostWorkDir -eq '') {
        $HostDir += @(($HostWorkDir, '/var/workdir/:rw') -join ':')
        $dockerArgs += @('--workdir', '/var/workdir/')
    }
    if ($HostDir.Length -gt 0) {
        $HostDir.ForEach(
            {
                $current = $_.Split(':')
                $currentHostDir = $current[0..1] -join ':'
                $currentRest = $current[2..($current.Length - 1)] -join ':'
                if (-not $currentHostDir -like "$env:SystemDrive\Users\*") {
                    Write-Error -Message 'Only support home directory.' -ErrorAction Stop
                }
                $currentHostDir = $currentHostDir. `
                    Replace("$env:SystemDrive\Users\", '/hosthome/'). `
                    Replace('\', '/')
                $dockerArgs += @('--volume', (($currentHostDir, $currentRest) -join ':'))
            }
        )
    }

    $dockerArgs += (
        $Image,
        $Command
    )

    if ($DryRun) {
        Write-Output $(@('docker', 'run' ) + $dockerArgs -join ' ')
    }
    else {
        docker run @dockerArgs
    }
}
