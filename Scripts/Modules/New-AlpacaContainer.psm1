function New-AlpacaContainer {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Project,
        [Parameter(Mandatory = $true)]
        [string] $Token,
        [Parameter(Mandatory = $false)]
        [string] $BuildMode
    )

    $owner = $env:GITHUB_REPOSITORY_OWNER
    $repository = $env:GITHUB_REPOSITORY
    $repository = $repository.replace($owner, "")
    $repository = $repository.replace("/", "")
    $branch = $env:GITHUB_HEAD_REF
    # $env:GITHUB_HEAD_REF is specified only for pull requests, so if it is not specified, use GITHUB_REF_NAME
    if (!$branch) {
        $branch = $env:GITHUB_REF_NAME
    }

    Write-AlpacaOutput "Creating container for project '$Project' of '$owner/$repository' on ref '$branch'"

    $headers = Get-AlpacaAuthenticationHeaders -Token $Token -Owner $owner -Repository $repository
    $headers.add("Content-Type", "application/json")

    $apiUrl = Get-AlpacaEndpointUrlWithParam -api 'alpaca' -Controller "Container" -Endpoint "Container"

    $request = @{
        owner                     = "$owner"
        type                      = "Build"
        containerOriginIdentifier = @{
            origin           = "GitHub"
            organizationId   = "$($env:GITHUB_REPOSITORY_OWNER_ID)"
            organizationName = $owner
            projectName      = $Project    
            repositoryId     = "$($env:GITHUB_REPOSITORY_ID)"
            repositoryName   = $repository
            branch           = $branch
            workflowName     = "$($env:GITHUB_WORKFLOW)"
            runId            = "$($env:GITHUB_RUN_ID)"
        }
    } 
    $body = $request | ConvertTo-Json -Depth 10
    $response = Invoke-RestMethod $apiUrl -Method 'POST' -Headers $headers -Body $body -AllowInsecureRedirect

    $container = [pscustomobject]@{
        Project   = $Project
        Id        = $response.id
        User      = $response.username
        Password  = $response.Password
        Url       = $response.webUrl
        BuildMode = "$BuildMode"
    }
    
    Write-AlpacaOutput "Created container '$($container.Id)'"

    return $container
}
Export-ModuleMember -Function New-AlpacaContainer