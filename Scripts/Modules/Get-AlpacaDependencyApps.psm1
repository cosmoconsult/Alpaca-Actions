function Get-AlpacaDependencyApps {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $PackagesFolder,
        [Parameter(Mandatory = $true)]
        [string] $Token
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
    $project = $env:ALGO_PROJECT

    Write-AlpacaOutput "Get container artifacts for $owner/$repository and ref $branch (project: $project)"

    $headers = Get-AlpacaAuthenticationHeaders -Token $Token -Owner $owner -Repository $repository
    $headers.add("Content-Type", "application/json")

    $config = Get-AlpacaConfigNameForWorkflowName 

    $request = @{
        source = @{
            owner = "$owner"
            repo = "$repository"
            branch = "$branch"
            project = "$($project -replace '^\.$', '_')"
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

    $QueryParams = @{
        "api-version" = "0.12"
    }
    $apiUrl = Get-AlpacaEndpointUrlWithParam -Controller "Container" -Endpoint "GitHub/GetBuildContainerArtifacts" -QueryParams $QueryParams
    $artifacts = Invoke-RestMethod $apiUrl -Method 'GET' -Headers $headers -Body $body -AllowInsecureRedirect

    foreach ($artifact in $artifacts) {
        if ($artifact.target -eq 'App') {
            if ($artifact.type -eq 'Url') {
                Write-AlpacaGroupStart "Downloading $($artifact.name) from $($artifact.url)"
                
                $tempArchive = "$([System.IO.Path]::GetTempFileName()).zip"
                $tempFolder = ([System.IO.Path]::GetRandomFileName())
                Invoke-WebRequest -Uri $artifact.url -OutFile $tempArchive
                Expand-Archive -Path $tempArchive -DestinationPath $tempFolder -Force

                Write-AlpacaOutput "Extracted files:"
                
                Get-ChildItem -Path $tempFolder -Recurse -File | ForEach-Object {
                    Write-AlpacaOutput "- $($_.FullName)"

                    # Move file to PackagesFolder
                    $destinationPath = Join-Path $PackagesFolder $_.Name
                    if (-not (Test-Path $destinationPath)) {
                        Write-AlpacaOutput "  Moving to PackagesFolder..."
                        Move-Item -Path $_.FullName -Destination $destinationPath -Force
                    }
                    else {
                        Write-AlpacaOutput "  Ignoring... file already exists in PackagesFolder"
                    }
                }

                # Clean up temporary files
                if (Test-Path $tempArchive) {
                    Remove-Item -Path $tempArchive -Force -ErrorAction SilentlyContinue
                }
                if (Test-Path $tempFolder) {
                    Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
                }

                Write-AlpacaGroupEnd
            }
            else {
                Write-AlpacaOutput "NuGet handled by AL-Go $($artifact.name)"
            }
        }
    }

    Write-AlpacaGroupStart "Files in PackagesFolder $PackagesFolder"
    $files = Get-ChildItem -Path $PackagesFolder -File
    foreach ($file in $files) {
        Write-AlpacaOutput "- $($file.Name)"
    }
    Write-AlpacaGroupEnd
}

Export-ModuleMember -Function Get-AlpacaDependencyApps