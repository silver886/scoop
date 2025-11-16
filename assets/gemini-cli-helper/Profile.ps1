[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$ProfileName = "Default",

    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Arg
)

$Shell = 'powershell'
if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    $Shell = 'pwsh'
}

& $Shell -NoProfile -Command {
    $UserProfileBak = $env:UserProfile
    $env:UserProfile = Join-Path $dir 'profiles' $ProfileName

    New-Item -ItemType Directory -Path $env:UserProfile -Force > $null
    gemini @Arg

    $env:UserProfile = $UserProfileBak
}
