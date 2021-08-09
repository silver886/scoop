function Connect-AWS {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Provider,

        [Parameter(Mandatory)]
        [string]$IdpAccount,

        [Parameter()]
        [string]$AwsProfilePrefix = ""
    )

    saml2aws login --config "$env:UserProfile\.saml2aws\$Provider.cfg" -a $IdpAccount --force
    $env:AWS_PROFILE = "$AwsProfilePrefix$IdpAccount"
    aws sts get-caller-identity
}
