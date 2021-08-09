function Convert-EOL {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [ValidateSet('mac', 'unix', 'win')]
        [string]$Os,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $Unix = (Get-Content $Path -Raw). `
        Replace("`r`n", "`n"). `
        Replace("`r", "`n")

    Switch ($Os) {
        'mac' {
            $Unix = $Unix.Replace("`n", "`r")
        }
        'win' {
            $Unix = $Unix.Replace("`n", "`r`n")
        }
    }

    Set-Content `
        -Path $Path `
        -Value $Unix `
        -NoNewline `
        -Force
}
