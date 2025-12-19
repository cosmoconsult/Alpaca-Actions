function Get-AlpacaSecretSyncStatus {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Token
    )

    Write-AlpacaOutput "Getting secret names from Alpaca backend"

    $headers = Get-AlpacaAuthenticationHeaders -Token $Token
    $apiUrl = Get-AlpacaEndpointUrlWithParam -Controller "GitHub" -Endpoint "SecretSync"
    try {
        return Invoke-AlpacaApiRequest -Url $apiUrl -Method Get -Headers $headers
    }
    catch {
        Write-AlpacaError "Failed to get secret sync status from Alpaca backend: $_"
        throw
    }
}
Export-ModuleMember -Function Get-AlpacaSecretSyncStatus
