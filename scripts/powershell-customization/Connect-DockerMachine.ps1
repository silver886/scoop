function Connect-DockerMachine {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]$Name,

        [switch]$Ssh
    )

    if ($Ssh) {
        docker-machine ssh $Name
    }
    else {
        docker-machine env $Name --shell powershell `
        | Invoke-Expression

        jq ".`"`"`"docker.host`"`"`"=`"`"`"$env:DOCKER_HOST`"`"`"" "$env:AppData\Code\User\settings.json" > "$env:AppData\Code\User\settings.json.tmp" && `
            Move-Item -Force -Path "$env:AppData\Code\User\settings.json.tmp" -Destination "$env:AppData\Code\User\settings.json"
        jq ".`"`"`"docker.certPath`"`"`"=`"`"`"$($env:DOCKER_CERT_PATH.replace('\', '/'))`"`"`"" "$env:AppData\Code\User\settings.json" > "$env:AppData\Code\User\settings.json.tmp" && `
            Move-Item -Force -Path "$env:AppData\Code\User\settings.json.tmp" -Destination "$env:AppData\Code\User\settings.json"
        jq ".`"`"`"docker.machineName`"`"`"=`"`"`"$env:DOCKER_MACHINE_NAME`"`"`"" "$env:AppData\Code\User\settings.json" > "$env:AppData\Code\User\settings.json.tmp" && `
            Move-Item -Force -Path "$env:AppData\Code\User\settings.json.tmp" -Destination "$env:AppData\Code\User\settings.json"
        jq ".`"`"`"docker.tlsVerify`"`"`"=`"`"`"$env:DOCKER_TLS_VERIFY`"`"`"" "$env:AppData\Code\User\settings.json" > "$env:AppData\Code\User\settings.json.tmp" && `
            Move-Item -Force -Path "$env:AppData\Code\User\settings.json.tmp" -Destination "$env:AppData\Code\User\settings.json"
    }
}
