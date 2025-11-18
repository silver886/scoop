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
    $MasterGeminiDir = Join-Path $env:UserProfile '.gemini'
    $env:UserProfile = Join-Path '$persist_dir' 'profiles' $Name
    $GeminiDir = Join-Path $env:UserProfile '.gemini'

    New-Item -ItemType Directory -Path $GeminiDir -Force > $null

    @(
        '.env',
        'settings.json'
    ) | ForEach-Object {
        $ConfigPath = Join-Path $GeminiDir $_
        if (-not (Test-Path $ConfigPath)) {
            Copy-Item -Path (Join-Path $MasterGeminiDir $_) -Destination $ConfigPath > $null
        }
    }

    dotenvx --quiet run --env-file (Join-Path $GeminiDir '.env') -- gemini @Arg
}.ToString().Replace('$Name', "'$Name'").Replace('@Arg', "$Arg")
