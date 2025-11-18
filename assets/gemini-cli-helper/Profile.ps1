[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Name,

    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Arg
)

$UserProfile = Join-Path '$persist_dir' 'profiles' $Name

$GeminiDir = Join-Path $UserProfile '.gemini'
New-Item -ItemType Directory -Path $GeminiDir -Force > $null

@(
    '.env',
    'settings.json'
) | ForEach-Object {
    $ConfigPath = Join-Path $GeminiDir $_
    if (-not (Test-Path $ConfigPath)) {
        Copy-Item -Path (Join-Path $env:UserProfile '.gemini' $_) -Destination $ConfigPath > $null
    }
}

$EnvPath = Join-Path $GeminiDir '.env'
dotenvx --quiet set --plain UserProfile $UserProfile --env-file $EnvPath

dotenvx --quiet run --overload --env-file $EnvPath -- gemini @Arg
