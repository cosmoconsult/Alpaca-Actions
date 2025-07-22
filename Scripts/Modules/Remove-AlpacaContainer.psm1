function Remove-AlpacaContainer {
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Container,
        [Parameter(Mandatory = $true)]
        [string] $Token
    )

    $owner = $env:GITHUB_REPOSITORY_OWNER
    $repository = $env:GITHUB_REPOSITORY
    $repository = $repository.replace($owner, "")
    $repository = $repository.replace("/", "")

    Write-Host "Deleting Container '$($Container.Id)' of project '$($Container.Project)'"

    $headers = Get-AlpacaAuthenticationHeaders -Token $Token -Owner $owner -Repository $repository

    $QueryParams = @{
        "api-version" = "0.12"
    }        
    $apiUrl = Get-AlpacaEndpointUrlWithParam -Controller "Container" -Ressource $Container.Id -QueryParams $QueryParams
    
    Invoke-RestMethod $apiUrl -Method 'DELETE' -Headers $headers -AllowInsecureRedirect | Out-Null

    Write-Host "Deleted Container '$($Container.Id)'"
}
Export-ModuleMember -Function Remove-AlpacaContainer