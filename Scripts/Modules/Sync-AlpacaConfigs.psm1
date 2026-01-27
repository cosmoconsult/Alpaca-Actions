function Sync-AlpacaConfigs {
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Secrets,
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Variables,
        [Parameter(Mandatory = $true)]
        [string] $Token
    )

    Write-AlpacaOutput "Syncing configs to Alpaca backend"

    $headers = Get-AlpacaAuthenticationHeaders -Token $Token
    $headers.add("Content-Type", "application/json")
    $apiUrl = Get-AlpacaEndpointUrlWithParam -Controller "GitHub" -Endpoint "ConfigSync"

    $body = @{ secrets = $Secrets; variables = $Variables } | ConvertTo-Json -Depth 10
    Invoke-AlpacaApiRequest -Url $apiUrl -Method Post -Headers $headers -Body $body | Out-Null

    Write-AlpacaOutput "Synced configs to Alpaca backend"
}
Export-ModuleMember -Function Sync-AlpacaConfigs