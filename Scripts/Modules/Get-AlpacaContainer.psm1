function Get-AlpacaContainer {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Token,
        [Parameter(Mandatory = $false)]
        [string]$alGoProject = "*", # TODO: rename
        [Parameter(Mandatory = $false)]
        [string]$alGoBuildMode = "*" # TODO: rename
    )

    $owner = $env:GITHUB_REPOSITORY_OWNER
    $repository = $env:GITHUB_REPOSITORY
    $repository = $repository.replace($owner, "")
    $repository = $repository.replace("/", "")

    try {
        Write-AlpacaGroupStart "Get Alpaca Containers of current build process for project '$alGoProject' and build mode '$alGoBuildMode'"

        $headers = Get-AlpacaAuthenticationHeaders -Token $Token
        $headers.add("Content-Type", "application/json")

        $apiUrl = Get-AlpacaEndpointUrlWithParam -Controller "Container" -Endpoint "Container/filter"

        $filter = @{
            organizationId = "$($env:GITHUB_REPOSITORY_OWNER_ID)"
            repoId         = "$($env:GITHUB_REPOSITORY_ID)"
            runId          = "$($env:GITHUB_RUN_ID)"
            podType        = "build"
        }
        $body = $filter | ConvertTo-Json -Compress
        $response = Invoke-AlpacaApiRequest -Url $apiUrl -Method 'POST' -Headers $headers -Body $body -Retries 3 -NoRetryStatusCodes @([System.Net.HttpStatusCode]::NotFound)
        Write-AlpacaOutput "Got $($response.Count) containers. Ids: $($response | ForEach-Object { $_.id } | ConvertTo-Json -Compress)"
        $responseInFilter = $response | Where-Object { $_.containerOriginIdentifier.alGoBuildMode -like $alGoBuildMode -and $_.containerOriginIdentifier.projectName -like $alGoProject }
        $container = $responseInFilter | ForEach-Object { [pscustomobject]@{
                Project   = $_.containerOriginIdentifier.projectName
                Id        = $_.id
                User      = $_.username
                Password  = $_.Password
                Url       = $_.webUrl
                BuildMode = $_.containerOriginIdentifier.alGoBuildMode
            } }
        Write-AlpacaDebug "Returning $($container.Count) container(s): $($container | ConvertTo-Json -Depth 10 -Compress)"
        return $container
    }
    finally {
        Write-AlpacaGroupEnd
    }
}
Export-ModuleMember -Function Get-AlpacaContainer