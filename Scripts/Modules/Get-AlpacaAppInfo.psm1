function Get-AlpacaAppInfo {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ContainerName,
        [Parameter(Mandatory = $true)]
        [string] $Token
    )
    process {
        $owner = $env:GITHUB_REPOSITORY_OWNER
        $repository = $env:GITHUB_REPOSITORY
        $repository = $repository.replace($owner, "")
        $repository = $repository.replace("/", "")

        $headers = Get-AlpacaAuthenticationHeaders -Token $Token -Owner $owner -Repository $repository
        $headers.add("accept", "application/text")

        $apiUrl = Get-AlpacaEndpointUrlWithParam -Api 'alpaca' -Controller "Container" -Endpoint "Exec" -Ressource $ContainerName -RouteSuffix "appInfo"
        Write-AlpacaOutput "Connecting to $apiUrl"
        $result = Invoke-RestMethod $apiUrl -Method 'Get' -Headers $headers -AllowInsecureRedirect
        return $result
    }
}

Export-ModuleMember -Function Get-AlpacaAppInfo