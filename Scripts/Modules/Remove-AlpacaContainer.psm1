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

    try {
        Write-AlpacaGroupStart "Deleting Container '$($Container.Id)' (Project: '$($Container.Project)', BuildMode: '$($Container.BuildMode)')"
        
        $headers = Get-AlpacaAuthenticationHeaders -Token $Token -Owner $owner -Repository $repository

        $apiUrl = Get-AlpacaEndpointUrlWithParam -Api 'alpaca' -Controller "Container" -Endpoint "Container" -Ressource $Container.Id
        
        Invoke-RestMethod $apiUrl -Method 'DELETE' -Headers $headers -AllowInsecureRedirect | Out-Null

        Write-AlpacaOutput "Deleted Container '$($Container.Id)'"
    } finally {
        Write-AlpacaGroupEnd
    }
}
Export-ModuleMember -Function Remove-AlpacaContainer