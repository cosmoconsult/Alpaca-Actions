function Get-AlpacaConfigSyncStatus {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Token
    )

    Write-AlpacaOutput "Getting config names from Alpaca backend"

    $headers = Get-AlpacaAuthenticationHeaders -Token $Token
    $apiUrl = Get-AlpacaEndpointUrlWithParam -Controller "GitHub" -Endpoint "ConfigSync"
    try {
        return Invoke-AlpacaApiRequest -Url $apiUrl -Method Get -Headers $headers
    }
    catch {
        Write-AlpacaError "Failed to get config sync status from Alpaca backend: $_"
        throw
    }
}
Export-ModuleMember -Function Get-AlpacaConfigSyncStatus
