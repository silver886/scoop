function Watch-AWS {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$AwsProfile,

        [Parameter(Mandatory)]
        [double]$Seconds,

        [string]$AwsProfileDescription
    )

    $already = $true
    while ((Get-AWSExpiration $AwsProfile -ErrorAction SilentlyContinue).Ticks -gt 0) {
        $already = $false
        Clear-Host
        Write-Output "STS profile $AwsProfile expired in $((Get-AWSExpiration $AwsProfile).ToString())"
        Start-Sleep $Seconds
    }
    if ($already) { return }

    if (-not $AwsProfileDescription) { $AwsProfileDescription = $AwsProfile }
    noti -t 'AWS Credential' -m "$AwsProfileDescription is expired"
}
