function Get-AWSExpiration {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$AwsProfile
    )

    return New-TimeSpan `
        -Start (Get-Date) `
        -End ([DateTime](Import-Ini `
            (Get-Content "$env:UserProfile\.aws\credentials")
        )[$AwsProfile].x_security_token_expires)
}
