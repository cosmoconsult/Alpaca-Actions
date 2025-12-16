function Get-AlpacaSecretSyncStatus {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Token
    )

    Write-AlpacaOutput "Getting secret names from Alpaca backend"

    $headers = Get-AlpacaAuthenticationHeaders -Token $Token
    $apiUrl = Get-AlpacaEndpointUrlWithParam -Api 'alpaca' -Controller "GitHub" -Endpoint "SecretSync"

    try {
        return Invoke-RestMethod $apiUrl -Method Get -Headers $headers -AllowInsecureRedirect
    }
    catch {
        Write-AlpacaError "Failed to get secret sync status from Alpaca backend: $($_.Exception.Message)"
        throw
    }
}
Export-ModuleMember -Function Get-AlpacaSecretSyncStatus
