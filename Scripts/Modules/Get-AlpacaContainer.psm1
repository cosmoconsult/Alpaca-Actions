function Get-AlpacaContainer {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Token,
        [Parameter(Mandatory = $false)]
        [string]$Project = "*",
        [Parameter(Mandatory = $false)]
        [string]$BuildMode = "*"
    )

    try {
        Write-AlpacaGroupStart "Get Alpaca Containers of current build process for project '$Project' and build mode '$BuildMode'"

        $headers = Get-AlpacaAuthenticationHeaders -Token $Token
        $headers.add("Content-Type", "application/json")

        $apiUrl = Get-AlpacaEndpointUrlWithParam -Controller "Container" -Endpoint "Container/filter"

        $filter = @{
            organizationId = "$($env:GITHUB_REPOSITORY_OWNER_ID)"
            repoId         = "$($env:GITHUB_REPOSITORY_ID)"
            runId          = "$($env:GITHUB_RUN_ID)"
            workflowName   = "$($env:GITHUB_WORKFLOW)"
            podType        = "build"
        }
        $body = $filter | ConvertTo-Json -Compress
        $response = Invoke-AlpacaApiRequest -Url $apiUrl -Method 'POST' -Headers $headers -Body $body -Retries 3 -NoRetryStatusCodes @([System.Net.HttpStatusCode]::NotFound)
        Write-AlpacaOutput "Got $($response.Count) containers. Ids: $($response | ForEach-Object { $_.id } | ConvertTo-Json -Compress)"
        $responseInFilter = $response | Where-Object { $_.containerOriginIdentifier.alGoBuildMode -like $BuildMode -and $_.containerOriginIdentifier.projectName -like $Project }
        $containers = @($responseInFilter | ForEach-Object { [pscustomobject]@{
                    Project   = $_.containerOriginIdentifier.projectName
                    Id        = $_.id
                    User      = $_.username
                    Password  = $_.Password
                    Url       = $_.webUrl
                    BuildMode = $_.containerOriginIdentifier.alGoBuildMode
                } })
        Write-AlpacaDebug "Returning $($containers.Count) container(s): $($containers | ConvertTo-Json -Depth 10 -Compress)"
        return $containers
    }
    finally {
        Write-AlpacaGroupEnd
    }
}
Export-ModuleMember -Function Get-AlpacaContainer