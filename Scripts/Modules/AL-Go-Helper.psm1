function Import-ALGoReadSettings {
    <#
    .SYNOPSIS
        Downloads and imports AL-Go modules from AL-Go-Actions based on the version in AL-Go-Settings.json.

    .DESCRIPTION
        Extracts the AL-Go version from the AL-Go-Settings.json file's $schema property,
        downloads the corresponding AL-Go module files (ReadSettings.psm1, DebugLogHelper.psm1, settings.schema.json)
        from GitHub into a temporary directory, and imports the ReadSettings module in global scope.
        Falls back to the main branch if the version cannot be determined or download fails.

    .PARAMETER Force
        Forces the download and import even if the ReadSettings command is already available.

    .EXAMPLE
        Import-ALGoReadSettings

    .EXAMPLE
        Import-ALGoReadSettings -Force

    .NOTES
        Downloads files to a temporary directory. The directory is not automatically cleaned up.
    #>

    [CmdletBinding()]
    param(
        [switch] $Force
    )

    # Check if ReadSettings command is already available
    $AlreadyAvailable = Get-Command ReadSettings -ErrorAction SilentlyContinue
    if ($AlreadyAvailable -and -not $Force) {
        Write-AlpacaDebug "ReadSettings command is already available. Skipping import."
        return
    }
    $RootSettingsPath = Join-Path $env:GITHUB_WORKSPACE ".github/AL-Go-Settings.json"
    if (-not (Test-Path $RootSettingsPath -PathType Leaf)) {
        Write-AlpacaNotice "Repo Settings file not found. Using 'main' branch for AL-Go modules."
        $specificVersion = 'main'
    }
    else {
        # Default to 'main' if we cannot determine the version from the $schema URL
        try {
            Write-AlpacaDebug "Read Settings to determine AL-Go version."
            $settings = Get-Content -Path $RootSettingsPath -Raw | ConvertFrom-Json
            $schemaUrl = $settings.'$schema'
            if ($schemaUrl -match '/microsoft/AL-Go-Actions/([^/]+)/') {
                $specificVersion = $Matches[1]
                Write-AlpacaDebug "Extracted version/ref: $specificVersion"
            }
            if ([string]::IsNullOrEmpty($specificVersion)) {
                Write-AlpacaDebug "Version/ref could not be extracted from schema url '$($schemaUrl)', fallback to 'main'"
                $specificVersion = 'main'
            }
        }
        catch {
            Write-AlpacaDebug "Version/ref could not be extracted from the schema url of the AL-Go settings, fallback to 'main'. Error: $($_.Exception.Message)"
            $specificVersion = 'main'
        }
    }

    # List of files to download from the determined version/ref
    $filesToDownload = @(
        '.Modules/ReadSettings.psm1',
        '.Modules/DebugLogHelper.psm1',
        '.Modules/settings.schema.json'
    )

    # Create a temporary directory to store the downloaded module files
    $TempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $TempDir | Out-Null

    $failedDownloads = @()
    $failedFallbackDownloads = @()

    foreach ($file in $filesToDownload) {
        $fileName = [System.IO.Path]::GetFileName($file)
        $tempFile = Join-Path $TempDir $fileName

        # Build list of versions to try: primary version, then 'main' as fallback
        $versionsToTry = @($specificVersion)
        if ($specificVersion -ne 'main') {
            $versionsToTry += 'main'
        }

        foreach ($version in $versionsToTry) {
            $url = "https://raw.githubusercontent.com/microsoft/AL-Go-Actions/$version/$file"
            Write-AlpacaDebug "Downloading $file from $url"

            try {
                Invoke-WebRequest -Uri $url -OutFile $tempFile -UseBasicParsing -ErrorAction Stop
                Write-AlpacaDebug "Successfully downloaded $file from $version"
                break #exit the loop if download succeeded
            }
            catch {
                $errorMessage = $_.Exception.Message
                Write-AlpacaDebug "Failed to download $file from $version. Error: $errorMessage"

                # Track failures: primary version goes to failedDownloads, fallback goes to failedFallbackDownloads
                if ($version -ne 'main') {
                    $failedDownloads += "$file ($version): $errorMessage"
                }
                else {
                    $failedFallbackDownloads += "$file ($version): $errorMessage"
                }
            }
        }
    }

    # Report all failed downloads
    if ($failedDownloads.Count -gt 0) {
        $failureList = $failedDownloads -join "`n  - "
        Write-AlpacaWarning "Failed to download the following AL-Go files:`n  - $failureList`nTry to download from main branch as fallback."
    }

    if ($failedFallbackDownloads.Count -gt 0) {
        $fallbackFailureList = $failedFallbackDownloads -join "`n  - "
        throw "Failed to download the following AL-Go files from the main branch as fallback:`n  - $fallbackFailureList"
    }

    # Import the ReadSettings module (and any others if needed)
    $readSettingsPath = Join-Path $TempDir 'ReadSettings.psm1'
    Import-Module $readSettingsPath -Scope Global -Force -DisableNameChecking -ErrorAction Stop
    Write-AlpacaDebug "Successfully imported ReadSettings module"

    # Not cleaning up is intentional since the schema file is needed when reading settings.
}
Export-ModuleMember -Function Import-ALGoReadSettings

function Get-IsAlpacaContainerRequired {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Settings
    )
    return -not ($Settings.useCompilerFolder -and $Settings.doNotPublishApps)
}
Export-ModuleMember -Function Get-IsAlpacaContainerRequired