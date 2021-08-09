Invoke-Expression (@(oh-my-posh --init --shell pwsh --config "$env:UserProfile\Documents\PowerShell\posh.json") -join "`n")

Import-Module "$($(Get-Item $(Get-Command scoop).Path).Directory.Parent.FullName)\modules\scoop-completion"

Import-Module posh-git
Import-Module posh-docker

Register-ArgumentCompleter -CommandName ssh, scp, sftp -Native -ScriptBlock {
    param($wordToComplete)
    $sshHosts = @()

    (Get-Content -Raw -Path ${Env:HomePath}\.ssh\config).Split("$([Environment]::NewLine)$([Environment]::NewLine)") `
    | ForEach-Object {
        $sshHost = $_.Split([Environment]::NewLine)
        $sshHosts += [PSCustomObject]@{
            Host   = $sshHost[0].Replace('Host ', '') ;
            Config = ($sshHost[1..$sshHost.Length] -join "`0").Replace("`t", '').Replace(' ', ': ').Replace(',', '').Replace("`0", "`n");
        }
    }

    $sshHosts `
    | Sort-Object -Unique -Property Host `
    | Where-Object { $_.Host -like "${wordToComplete}*" } `
    | ForEach-Object {
        New-Object -Type System.Management.Automation.CompletionResult -ArgumentList $_.Host,
        $_.Host,
        'ParameterValue',
        $_.Config
    }
}
