function Get-AlpacaAppInfo {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ContainerName,
        [Parameter(Mandatory = $true)]
        [string] $Token
    )
    process {
        $headers = Get-AlpacaAuthenticationHeaders -Token $Token
        $headers.add("accept", "application/text")

        $apiUrl = Get-AlpacaEndpointUrlWithParam -Api 'alpaca' -Controller "Container" -Endpoint "Exec" -Ressource $ContainerName -RouteSuffix "appInfo"
        Write-AlpacaOutput "Connecting to $apiUrl"
        $result = Invoke-AlpacaApiRequest -Url $apiUrl -Method 'Get' -Headers $headers
        return $result
    }
}

Export-ModuleMember -Function Get-AlpacaAppInfo