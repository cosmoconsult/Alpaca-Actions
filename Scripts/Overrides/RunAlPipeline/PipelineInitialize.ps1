param(
    [Parameter(Mandatory = $true)]
    [hashtable] $Jobs,
    [Parameter(Mandatory = $true)]
    [string] $ScriptsPath
)

Import-Module (Join-Path $ScriptsPath "Modules/Alpaca.psd1") -Scope Global -DisableNameChecking

function ConvertTo-AlpacaSecurePassword {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Password value is a runtime secret provided by AL-Go, not a literal plaintext string')]
    param([string] $PlainText)
    return ConvertTo-SecureString -String $PlainText -AsPlainText
}

function Set-ParentContextVariable {
    param(
        [string] $Name,
        [object] $Value
    )
    $oldValue = Get-Variable -Name $Name -ValueOnly -Scope 2 -ErrorAction Ignore
    Write-AlpacaDebug "Old value of parent variable '$Name':`n$( ConvertTo-AlpacaOutputString $oldValue )"
    Write-AlpacaDebug "New value of parent variable '$Name':`n$( ConvertTo-AlpacaOutputString $Value )"
    Set-Variable -Name $Name -Value $Value -Scope 2
}



# Check parent context (Variables & Settings)
try {
    Write-AlpacaGroupStart "Check parent context (Variables & Settings)"

    if ($additionalCountries -is [String]) { $additionalCountries = @($additionalCountries.Split(',').Trim() | Where-Object { $_ }) }
    if ($additionalCountries.Length -gt 0) {
        Write-AlpacaDebug "Additional countries specified: $($additionalCountries -join ', ')"
        throw "The AL-Go setting 'additionalCountries' is not supported by COSMO Alpaca. Use 'buildModes' to validate additional countries instead. https://docs.cosmoconsult.com/en-en/cloud-service/alpaca/github/"
    }
} finally {
    Write-AlpacaGroupEnd
}



# Collect parent context Information
try {
    Write-AlpacaGroupStart "Collect parent context Information"

    Write-AlpacaOutput "Get GitHub token from environment variable"
    $token = $env:_token

    Write-AlpacaOutput "Get AL-Go project from environment variable"
    $project = $env:_project
    Write-AlpacaDebug "AL-Go project is '$project'"

    Write-AlpacaOutput "Get AL-Go build mode from environment variable"
    $buildMode = $env:_buildMode
    Write-AlpacaDebug "AL-Go build mode is '$buildMode'"

    Write-AlpacaOutput "Get COSMO Alpaca backend url from outputs of initialization job"
    $backendUrl = $Jobs.initialization.outputs.backendUrl
    Write-AlpacaDebug "COSMO Alpaca backend url is '$backendUrl'"
    Write-AlpacaDebug "Set environment variable 'ALPACA_BACKEND_URL' to '$backendUrl'"
    $env:ALPACA_BACKEND_URL = $backendUrl

    Write-AlpacaOutput "Get AL-Go settings"
    $settings = $env:Settings | ConvertFrom-Json
    Write-AlpacaDebug "AL-Go settings: $($settings | ConvertTo-Json -Depth 10 -Compress)"

    Write-AlpacaOutput "Get AL-Go Alpaca settings"
    $alpacaSettings = Get-AlpacaALGoSettings -Settings $settings
    Write-AlpacaDebug "AL-Go Alpaca settings: $($alpacaSettings | ConvertTo-Json -Depth 10 -Compress)"
} finally {
    Write-AlpacaGroupEnd
}



# Handle COSMO Alpaca container
try {
    Write-AlpacaGroupStart "Handle COSMO Alpaca container"

    if ((Get-IsAlpacaContainerRequired -Settings $settings)) {
        Write-AlpacaOutput "Container is required based on settings"
        $containers = @(Get-AlpacaContainer -Project $project -Token $token -BuildMode $buildMode)
        if ($containers.Count -gt 1) {
            throw "Multiple containers found for project '$project' and build mode '$buildMode'. Expected at most one container, but found $($containers.Count)."
        }
        elseif ($containers.Count -eq 1) {
            $container = $containers[0]
            Write-AlpacaOutput "Container with ID '$($container.Id)' exists for project '$project' and build mode '$buildMode'."
        }
        else {
            Write-AlpacaOutput "Creating new container for project '$project' and build mode '$buildMode'"
            $container = New-AlpacaContainer -Project $project -Token $token -BuildMode $buildMode
        }
    }
    else {
        Write-AlpacaOutput "No container required based on settings"
        $container = @{
            Id       = "NOCONTAINER"
            User     = "NOCONTAINER"
            Password = "NOCONTAINER"
            Url      = "https://NOCONTAINER"
        }
    }

    Write-AlpacaDebug "Container information: $($container | ConvertTo-Json -Depth 10 -Compress)"

    Write-AlpacaOutput "Get container authentication context from container information"
    $containerAuthContext = @{
        username = $container.User
        Password = ConvertTo-AlpacaSecurePassword -PlainText $container.Password
    }

    Write-AlpacaDebug "Container authentication context: $($containerAuthContext | ConvertTo-Json -Depth 10 -Compress)"

    # Update parent context
    try {
        Write-AlpacaGroupStart "Update parent context"

        Write-AlpacaOutput "Set environment variable 'ALPACA_CONTAINER_ID' to '$($container.Id)'"
        $env:ALPACA_CONTAINER_ID = $container.Id

        Write-AlpacaOutput "Set parent variable 'bcAuthContext' to '$([pscustomobject]$containerAuthContext)'"
        Set-ParentContextVariable -Name 'bcAuthContext' -Value $containerAuthContext

        Write-AlpacaOutput "Set parent variable 'environment' to '$($container.Url)'"
        Set-ParentContextVariable -Name 'environment' -Value $container.Url
    } finally {
        Write-AlpacaGroupEnd
    }
} finally {
    Write-AlpacaGroupEnd
}



# Initialize Packages folder with COSMO Alpaca artifacts
try {
    Write-AlpacaGroupStart "Initialize Packages folder with COSMO Alpaca artifacts"

    Write-AlpacaOutput "Get Packages folder"
    $packagesFolder = CheckRelativePath -baseFolder $baseFolder -sharedFolder $sharedFolder -path $packagesFolder -name "packagesFolder"
    if (Test-Path $packagesFolder) {
        Remove-Item $packagesFolder -Recurse -Force
    }
    New-Item $packagesFolder -ItemType Directory | Out-Null
    Write-AlpacaOutput "Packages folder is '$packagesFolder'"

    Write-AlpacaOutput "Download COSMO Alpaca artifacts"
    Get-AlpacaDependencyApps -packagesFolder $packagesFolder -token $token
} finally {
    Write-AlpacaGroupEnd
}



try {
    # Prepare previous versions for apps
    Write-AlpacaGroupStart "Prepare previous versions for apps"

    $downloadPreviousVersions = -not $settings.skipUpgrade -and $alpacaSettings.useNuGetFeedsForUpgrade

    if ($downloadPreviousVersions) {
        $previousVersionsFolder = CheckRelativePath -baseFolder $baseFolder -sharedFolder $sharedFolder -path '.alpaca-previous-versions' -name "previousVersionsFolder"
        if (Test-Path $previousVersionsFolder) {
            Remove-Item $previousVersionsFolder -Recurse -Force
        }
        New-Item $previousVersionsFolder -ItemType Directory | Out-Null
        Write-AlpacaOutput "Previous versions folder: '$previousVersionsFolder'"

        $appVersionMask = @{
            Major    = $( if ($appVersion) { ([System.Version]$appVersion).Major } else { -1 } )
            Minor    = $( if ($appVersion) { ([System.Version]$appVersion).Minor } else { -1 } )
            Build    = $( if ([string]::IsNullOrEmpty($appBuild)) { -1 } else { [int]$appBuild } )
            Revision = $( if ([string]::IsNullOrEmpty($appRevision)) { -1 } else { [int]$appRevision } )
        }
        Write-AlpacaDebug "AL-Go app version mask: $($appVersionMask.Major).$($appVersionMask.Minor).$($appVersionMask.Build).$($appVersionMask.Revision)"

        $allAppFolders = @(($appFolders + $testFolders + $bcptTestFolders)
            | ForEach-Object { CheckRelativePath -baseFolder $baseFolder -sharedFolder $sharedFolder -path $_ -name "App folder" }
            | Where-Object { Test-Path $_ })
        Write-AlpacaDebug "AL-Go app folders, test folders and BCPT test folders: $($allAppFolders -join ', ')"

        foreach($appFolder in $allAppFolders) {
            # Download previous version for app folder
            Write-AlpacaGroupStart "Download previous version for app folder '$appFolder'"

            $appJson = Read-AppManifest -Path (Join-Path $appFolder "app.json")
            if (!$appJson) {
                continue;
            }
            Write-AlpacaDebug "App manifest: $($appJson | ConvertTo-Json -Depth 10 -Compress)"

            $appJsonVersion = [System.Version]$appJson.version
            $appJson.version = [System.Version]::new(
                $( if ($appVersionMask.Major -ne -1) { $appVersionMask.Major } else { $appJsonVersion.Major } ),
                $( if ($appVersionMask.Minor -ne -1) { $appVersionMask.Minor } else { $appJsonVersion.Minor } ),
                $( if ($appVersionMask.Build -ne -1) { $appVersionMask.Build } else { $appJsonVersion.Build } ),
                $( if ($appVersionMask.Revision -ne -1) { $appVersionMask.Revision } else { $appJsonVersion.Revision } )
            )

            Write-AlpacaOutput "Current Version: $($appJson.publisher), $($appJson.name), $($appJson.id), $($appJson.version)"

            $previousAppInfo = $null

            if ($alpacaSettings.useNuGetFeedsForUpgrade) {
                # Download previous version from trusted NuGet feeds
                Write-AlpacaGroupStart "Download previous version from trusted NuGet feeds"

                $downloadParams = @{
                    packageName = $appJson.id
                    version = "(,$($appJson.version))"
                    select = 'Latest'
                    folder = $previousVersionsFolder
                    downloadDependencies = 'none'
                }
                Write-AlpacaDebug "Parameters: $($downloadParams | ConvertTo-Json -Depth 10 -Compress)"

                $previousAppInfo = Download-BcNuGetPackageToFolder @downloadParams *>&1 | Invoke-AlpacaOutputHandler

                Write-AlpacaGroupEnd
            }

            if ($previousAppInfo) {
                Write-AlpacaOutput "Previous Version: $($previousAppInfo.publisher), $($previousAppInfo.name), $($previousAppInfo.id), $($previousAppInfo.version)"
            } else {
                Write-AlpacaWarning "No previous version for app folder '$appFolder' found."
            }

            Write-AlpacaGroupEnd
        }

        # Show downloaded previous versions of apps
        try {
            Write-AlpacaGroupStart "Downloaded files in previous versions folder '$previousVersionsFolder'"

            $files = Get-ChildItem -Path $previousVersionsFolder -Recurse -File
            foreach ($file in $files) {
                Write-AlpacaOutput "- $($file.Name)"
            }
            if (!$files) {
                Write-AlpacaOutput "No files found in previous versions folder '$previousVersionsFolder'"
            }

        } finally {
            Write-AlpacaGroupEnd
        }

        # Update parent context
        try {
            Write-AlpacaGroupStart "Update parent context"

            Write-AlpacaOutput "Set parent variable 'previousApps' to '$previousVersionsFolder'"
            Set-ParentContextVariable -Name 'previousApps' -Value @($previousVersionsFolder)

        } finally {
            Write-AlpacaGroupEnd
        }
    } else {
        Write-AlpacaOutput "No download of previous versions for apps required based on settings"
    }
} finally {
    Write-AlpacaGroupEnd
}



# Load COSMO Alpaca overrides
try {
    Write-AlpacaGroupStart "Load COSMO Alpaca overrides"

    $overridesPath = Join-Path $ScriptsPath "Overrides/RunAlPipeline"

    Write-AlpacaOutput "Load COSMO Alpaca overrides from $(Resolve-Path $overridesPath -Relative)"

    Get-Item -Path $overridesPath |
    Get-ChildItem -Filter "*.ps1" -Exclude "PipelineInitialize.*" -File |
    ForEach-Object {
        $scriptPath = $_.FullName
        $scriptName = $_.BaseName

        # Load COSMO Alpaca override
        Write-AlpacaGroupStart "Load COSMO Alpaca override for '$scriptName'"

        Write-AlpacaOutput "Get COSMO Alpaca override from file '$(Resolve-Path $scriptPath -Relative)'"
        $scriptBlock = Get-Command $scriptPath | Select-Object -ExpandProperty ScriptBlock

        # Get existing override from parent context
        try {
            Write-AlpacaGroupStart "Get existing override from variable '$scriptName' in parent context"

            $existingScriptBlock = Get-Variable -Name $scriptName -ValueOnly -Scope 1 -ErrorAction Ignore
            if ($existingScriptBlock) {
                Write-AlpacaOutput $existingScriptBlock.ToString()
            }
            else {
                Write-AlpacaOutput "None"
            }
        } finally {
            Write-AlpacaGroupEnd
        }

        # Update parent context
        try {
            Write-AlpacaGroupStart "Update parent context"

            Write-AlpacaOutput "Set parent variable '$scriptName' to COSMO Alpaca override"
            Set-ParentContextVariable -Name $scriptName -Value $scriptBlock

            Write-AlpacaOutput "Set parent variable 'AlGo$ScriptName' to existing AL-Go override"
            Set-ParentContextVariable -Name "AlGo$scriptName" -Value $existingScriptBlock
        } finally {
            Write-AlpacaGroupEnd
        }

        Write-AlpacaGroupEnd
    }
} finally {
    Write-AlpacaGroupEnd
}
