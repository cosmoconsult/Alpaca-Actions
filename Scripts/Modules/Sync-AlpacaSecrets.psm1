function Sync-AlpacaSecrets {
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Secrets,
        [Parameter(Mandatory = $true)]
        [string] $Token
    )

    Write-AlpacaOutput "Syncing secrets to Alpaca backend"

    $headers = Get-AlpacaAuthenticationHeaders -Token $Token
    $headers.add("Content-Type", "application/json")
    $apiUrl = Get-AlpacaEndpointUrlWithParam -Api 'alpaca' -Controller "GitHub" -Endpoint "SecretSync"

    $body = @{ secrets = $Secrets } | ConvertTo-Json -Depth 10
    Invoke-RestMethod $apiUrl -Method Post -Headers $headers -AllowInsecureRedirect -Body $body | Out-Null

    Write-AlpacaOutput "Synced secrets to Alpaca backend"
}
Export-ModuleMember -Function Sync-AlpacaSecrets