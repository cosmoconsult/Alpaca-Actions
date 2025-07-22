function New-AlpacaContainer {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Project,
        [Parameter(Mandatory = $true)]
        [string] $Token
    )

    $owner = $env:GITHUB_REPOSITORY_OWNER
    $repository = $env:GITHUB_REPOSITORY
    $repository = $repository.replace($owner, "")
    $repository = $repository.replace("/", "")
    $branch = $env:GITHUB_HEAD_REF
    # $Env:GITHUB_HEAD_REF is specified only for pull requests, so if it is not specified, use GITHUB_REF_NAME
    if (!$branch) {
        $branch = $env:GITHUB_REF_NAME
    }

    Write-Host "Creating container for project '$Project' of '$owner/$repository' on ref '$branch'"

    $headers = Get-AlpacaAuthenticationHeaders -Token $Token -Owner $owner -Repository $repository
    $headers.add("Content-Type", "application/json")

    $config = Get-AlpacaConfigNameForWorkflowName 

    $QueryParams = @{
        "api-version" = "0.12"
    }
    $apiUrl = Get-AlpacaEndpointUrlWithParam -Controller "Container" -Endpoint "GitHub/Build" -QueryParams $QueryParams

    $request = @{
        source = @{
            owner = "$owner"
            repo = "$repository"
            branch = "$branch"
            project = "$($Project -replace '^\.$', '_')"
        }
        containerConfiguration = "$config"
        workflow = @{
            actor = "$($env:GITHUB_ACTOR)"
            workflowName = "$($env:GITHUB_WORKFLOW)"
            WorkflowRef = "$($env:GITHUB_WORKFLOW_REF)"
            RunID = "$($env:GITHUB_RUN_ID)"
            Repository = "$($env:GITHUB_REPOSITORY)"
        }
    }
    
    $body = $request | ConvertTo-Json -Depth 10
    $response = Invoke-RestMethod $apiUrl -Method 'POST' -Headers $headers -Body $body -AllowInsecureRedirect

    $container = [pscustomobject]@{
        Project = $Project
        Id = $response.id
        User = $response.username
        Password = $response.Password
        Url = $response.webUrl
    }
    
    Write-Host "Created container '$($container.Id)'"

    return $container
}
Export-ModuleMember -Function New-AlpacaContainer