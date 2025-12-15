function Get-AlpacaSyncedSecretNames {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Token
    )

    Write-AlpacaOutput "Getting secret names from Alpaca backend"

    $headers = Get-AlpacaAuthenticationHeaders -Token $Token
    $apiUrl = Get-AlpacaEndpointUrlWithParam -Api 'alpaca' -Controller "GitHub" -Endpoint "SecretSync"

    try {
        $response = Invoke-RestMethod $apiUrl -Method Get -Headers $headers -AllowInsecureRedirect
        
        if ($response -and $response.secretNames) {
            Write-AlpacaOutput "Retrieved $($response.secretNames.Count) secret names from Alpaca backend"
            return $response.secretNames
        }
        else {
            Write-AlpacaOutput "No secret names found in Alpaca backend"
            return @()
        }
    }
    catch {
        Write-AlpacaError "Failed to get secret names from Alpaca backend: $($_.Exception.Message)"
        throw
    }
}
Export-ModuleMember -Function Get-Alpaca-SyncedSecretNames
