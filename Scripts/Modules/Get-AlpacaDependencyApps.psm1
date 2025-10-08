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
    $project = $env:_project

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
                
                # Make a web request to get the content and headers
                $response = Invoke-WebRequest -Uri $artifact.url

                # Determine file type based on Content-Disposition header or content signature
                $fileType = ''
                $contentDisposition = $response.Headers["Content-Disposition"]
                if ($contentDisposition -is [string[]]) {
                    # If it's an array, take the first element. This is required for compatibility with PowerShell 5.1. Headers are return as array in pwsh 7 and return as string in Windows PowerShell 5.1
                    $contentDisposition = $contentDisposition[0]
                }
                switch ($true) {
                    { $contentDisposition -and $contentDisposition.EndsWith(".zip") } {
                        Write-AlpacaOutput "Detected zip file from Content-Disposition header"
                        $fileType = 'zip'
                        break
                    }
                    { $contentDisposition -and $contentDisposition.EndsWith(".app") } {
                        Write-AlpacaOutput "Detected .app file from Content-Disposition header"
                        $fileType = 'app'
                        break
                    }
                    { ($response.Content.Length -ge 4) -and ([string]::new([char[]]($response.Content[0..3])) -eq "NAVX") } {
                        Write-AlpacaOutput "Detected .app file from content signature"
                        $fileType = 'app'
                        break
                    }
                    { ($response.Content.Length -ge 2) -and ([string]::new([char[]]($response.Content[0..1])) -eq "PK") } {
                        Write-AlpacaOutput "Detected zip file from content signature"
                        $fileType = 'zip'
                        break
                    }
                    Default {
                        $fileType = 'unknown'
                    }
                }

                switch ($fileType) {
                    'app' {
                        # Extract filename from Content-Disposition or use artifact name
                        $filename = "$($artifact.name).app"
                        if ($contentDisposition -match 'filename\*?=(?:"?)([^";]+)(?:"?)') {
                            $filename = $matches[1]
                            # Remove UTF-8'' prefix if present (for filename*= format)
                            if ($filename -like 'UTF-8''*') {
                                $filename = $filename.Substring(7)
                            }
                            # Handle URL-encoded filenames (if filename*= was used)
                            if ($contentDisposition -match 'filename\*=') {
                                $filename = [System.Web.HttpUtility]::UrlDecode($filename)
                            }
                        }
                        $destinationPath = Join-Path $PackagesFolder $filename
                    
                        if (-not (Test-Path $destinationPath)) {
                            Write-AlpacaOutput "  Saving .app file directly to PackagesFolder..."
                            [System.IO.File]::WriteAllBytes($destinationPath, $response.Content)
                            Write-AlpacaOutput "- $destinationPath"
                        }
                        else {
                            Write-AlpacaOutput "  Ignoring... file already exists in PackagesFolder"
                        }
                    }
                    'zip' {
                        # Save content to temporary zip file and extract
                        $tempArchive = "$([System.IO.Path]::GetTempFileName()).zip"
                        $tempFolder = ([System.IO.Path]::GetRandomFileName())
                        [System.IO.File]::WriteAllBytes($tempArchive, $response.Content)
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
                    }
                    Default {
                        Write-AlpacaOutput "Unknown file type"
                    }
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