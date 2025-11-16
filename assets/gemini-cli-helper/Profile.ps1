[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Name,

    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Arg
)

$Shell = 'powershell'
if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    $Shell = 'pwsh'
}

& $Shell -NoProfile -Command {
    $env:UserProfile = Join-Path $dir 'profiles' $Name

    New-Item -ItemType Directory -Path $env:UserProfile -Force > $null
    gemini @Arg
}.ToString().Replace('$Name', "'$Name'").Replace('@Arg', "$Arg")
