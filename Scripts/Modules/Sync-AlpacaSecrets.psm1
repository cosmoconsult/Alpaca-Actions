function Sync-AlpacaSecrets {
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Secrets,
        [Parameter(Mandatory = $true)]
        [string] $Token
    )

    $owner = $env:GITHUB_REPOSITORY_OWNER
    $repository = $env:GITHUB_REPOSITORY
    $repository = $repository.replace($owner, "")
    $repository = $repository.replace("/", "")

    Write-AlpacaOutput "Syncing secrets for repository '$($owner)/$($repository)'"

    $headers = Get-AlpacaAuthenticationHeaders -Token $Token
    $headers.add("Content-Type", "application/json")
    $apiUrl = Get-AlpacaEndpointUrlWithParam -Api 'alpaca' -Controller "GitHub" -Endpoint "SecretSync"

    $request = @{
        secrets = $Secrets
    }
    
    $body = $request | ConvertTo-Json -Depth 10
    Invoke-RestMethod $apiUrl -Method Post -Headers $headers -AllowInsecureRedirect -Body $body | Out-Null

    Write-AlpacaOutput "Synced secrets for repository '$($owner)/$($repository)'"
}
Export-ModuleMember -Function Sync-AlpacaSecrets