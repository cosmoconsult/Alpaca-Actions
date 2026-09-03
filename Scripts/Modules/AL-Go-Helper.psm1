$script:AlGoTempDir = $null

$script:DebugLogHelperFiles = @(
    '.Modules/DebugLogHelper.psm1'
) | Select-Object -Unique

$script:AlGoReadSettingsFiles = @(
    '.Modules/ReadSettings.psm1',
    '.Modules/settings.schema.json'
) + $script:DebugLogHelperFiles | Select-Object -Unique

$script:AlGoGitHubHelperFiles = @(
    'Github-Helper.psm1'
) + $script:DebugLogHelperFiles | Select-Object -Unique

$script:AlGoHelperFiles = @(
    'AL-Go-Helper.ps1'
) + $script:DebugLogHelperFiles + $script:AlGoGitHubHelperFiles + $script:AlGoReadSettingsFiles | Select-Object -Unique

$script:AlGoCommandFileMap = @{
    'ReadSettings'              = $script:AlGoReadSettingsFiles
    'Get-ContentLF'             = $script:AlGoGitHubHelperFiles
    'Set-JsonContentLF'         = $script:AlGoGitHubHelperFiles
    'invoke-git'                = $script:AlGoGitHubHelperFiles
    'GetAccessToken'            = $script:AlGoGitHubHelperFiles
    'CloneIntoNewFolder'        = $script:AlGoHelperFiles
    'CommitFromNewFolder'       = $script:AlGoHelperFiles
    'ConvertTo-HashTable'       = $script:AlGoHelperFiles
    'GetProjectsFromRepository' = $script:AlGoHelperFiles
    'ResolveProjectFolders'     = $script:AlGoHelperFiles
}
function Save-ALGoFiles {
    <#
    .SYNOPSIS
        Downloads AL-Go files from AL-Go-Actions based on the version in AL-Go-Settings.json.

    .DESCRIPTION
        Extracts the AL-Go version from the AL-Go-Settings.json file's $schema property,
        downloads the given AL-Go files from GitHub into a temporary directory.
        Falls back to the main branch if the version cannot be determined or download fails.

    .PARAMETER Files
        An array of relative file paths to download from the AL-Go-Actions repository.

    .EXAMPLE
        Save-ALGoFiles -Files '.Modules/ReadSettings.psm1', '.Modules/DebugLogHelper.psm1', '.Modules/settings.schema.json'

    .NOTES
        Downloads files to a temporary directory. The directory is not automatically cleaned up.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Files
    )

    $rootSettingsPath = Join-Path $env:GITHUB_WORKSPACE ".github/AL-Go-Settings.json"
    if (-not (Test-Path $rootSettingsPath -PathType Leaf)) {
        Write-AlpacaNotice "Repo Settings file not found. Using 'main' branch for AL-Go modules."
        $specificVersion = 'main'
    }
    else {
        # Default to 'main' if we cannot determine the version from the $schema URL
        try {
            Write-AlpacaDebug "Read Settings to determine AL-Go version."
            $settings = Get-Content -Path $rootSettingsPath -Raw | ConvertFrom-Json
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

    # Reuse cached temp directory or create a new one
    if ($script:AlGoTempDir -and (Test-Path $script:AlGoTempDir)) {
        $tempDir = $script:AlGoTempDir
    }
    else {
        $tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        $script:AlGoTempDir = $tempDir
    }

    $failedDownloads = @()
    $failedFallbackDownloads = @()

    foreach ($file in $Files) {
        $tempFile = Join-Path $tempDir $file

        # Skip files that have already been downloaded
        if (Test-Path $tempFile) {
            Write-AlpacaDebug "File $file already exists in cache. Skipping download."
            continue
        }

        $tempFileDir = Split-Path -Path $tempFile -Parent
        if (-not (Test-Path $tempFileDir)) {
            New-Item -Path $tempFileDir -ItemType Directory -Force | Out-Null
        }

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
}
Export-ModuleMember -Function Save-ALGoFiles

function Import-ALGoFiles {
    <#
    .SYNOPSIS
        Downloads and imports AL-Go files from AL-Go-Actions.

    .DESCRIPTION
        Downloads the specified files using Save-ALGoFiles (with caching) and imports
        all .psm1 and .ps1 files into global scope. .psm1 files are imported first
        (as modules), then .ps1 files (as dynamic modules via New-Module).
        Non-script files (e.g., .json) are downloaded but not imported.

    .PARAMETER Files
        An array of relative file paths to download and import from the AL-Go-Actions repository.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Files,

        [switch] $Force
    )

    Save-ALGoFiles -Files $Files

    $psm1Files = $Files | Where-Object { $_ -like '*.psm1' }
    $ps1Files = $Files | Where-Object { $_ -like '*.ps1' }

    # Import .psm1 modules first (dependencies like Github-Helper before AL-Go-Helper)
    foreach ($file in $psm1Files) {
        $filePath = Join-Path $script:AlGoTempDir $file
        Import-Module $filePath -Global -Force:$Force -DisableNameChecking -ErrorAction Stop
        Write-AlpacaDebug "Successfully imported module: $file"
    }

    # Import .ps1 scripts only if no matching .psm1 file exists in the list
    foreach ($file in $ps1Files) {
        $matchingPsm1 = [System.IO.Path]::ChangeExtension($file, '.psm1')
        if ($psm1Files -contains $matchingPsm1) {
            Write-AlpacaDebug "Skipping $file because matching module $matchingPsm1 is already imported."
            continue
        }
        $filePath = Join-Path $script:AlGoTempDir $file
        $dynamicModuleName = "ALGoDynamicModule_$(Split-Path $filePath -Leaf)"
        if ($Force) {
            Remove-Module -Name $dynamicModuleName -Force -ErrorAction SilentlyContinue
        }
        if (-not (Get-Module -Name $dynamicModuleName -ErrorAction SilentlyContinue)) {
            New-Module -ScriptBlock ([scriptblock]::Create(". '$filePath'")) -Name $dynamicModuleName | Import-Module -Global -DisableNameChecking -ErrorAction Stop
            Write-AlpacaDebug "Successfully imported script as module: $file"
        }
        else {
            Write-AlpacaDebug "Module $dynamicModuleName already exists. Skipping import of $file."
        }
    }
}

function Import-ALGoCommands {
    <#
    .SYNOPSIS
        Ensures the specified AL-Go commands are available by downloading and importing the required files.

    .DESCRIPTION
        Looks up each command in the command-to-files mapping, collects all required files,
        downloads them (with caching), and imports them into global scope.
        Commands that are already available are skipped unless -Force is specified.

    .PARAMETER Commands
        An array of AL-Go command names to make available (e.g., 'ReadSettings', 'Get-ContentLF').

    .PARAMETER Force
        Forces the download and import even if the commands are already available.

    .EXAMPLE
        Import-ALGoCommands -Commands 'ReadSettings'

    .EXAMPLE
        Import-ALGoCommands -Commands 'Get-ContentLF', 'CloneIntoNewFolder', 'CommitFromNewFolder'

    .EXAMPLE
        Import-ALGoCommands -Commands 'ReadSettings' -Force
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Commands,

        [switch] $Force
    )

    foreach ($command in $Commands) {
        if (-not $Force) {
            $alreadyAvailable = Get-Command $command -ErrorAction SilentlyContinue
            if ($alreadyAvailable) {
                Write-AlpacaDebug "$command command is already available. Skipping import."
                continue
            }
        }

        $files = $script:AlGoCommandFileMap[$command]
        if (-not $files) {
            throw "Unknown AL-Go command '$command'. Add it to the command file map in AL-Go-Helper.psm1."
        }

        Import-ALGoFiles -Files $files -Force:$Force
    }
}
Export-ModuleMember -Function Import-ALGoCommands

function Invoke-ALGoCommand {
    <#
    .SYNOPSIS
        Invokes an AL-Go command in a script block, ensuring the command is available.

    .DESCRIPTION
        Ensures the specified AL-Go command is available by importing the required files,
        then invokes the provided script block, passing any pipeline input to it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock] $ScriptBlock,

        [Parameter(ValueFromPipeline = $true)]
        [object] $InputObject = $null
    )

    begin {
        $commandAst = $ScriptBlock.Ast.Find({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
        $commandName = $commandAst.GetCommandName()
        if (-not $commandName) {
            throw "Could not determine command name from script block."
        }

        Import-ALGoCommands -Commands $commandName
    }

    process {
        ($InputObject | ForEach-Object $ScriptBlock) *>&1 | Invoke-AlpacaOutputHandler
    }
}
Export-ModuleMember -Function Invoke-ALGoCommand

function Get-IsAlpacaContainerRequired {
    [CmdletBinding()]
    [OutputType([Boolean])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Settings
    )
    return -not ($Settings.useCompilerFolder -and $Settings.doNotPublishApps)
}
Export-ModuleMember -Function Get-IsAlpacaContainerRequired

function Get-AlpacaALGoSettings {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    $defaultAlpacaSettings = [ordered]@{
        useNuGetFeedsForUpgrade                = $false
        startupScriptUrl                       = ''
        actionOnMissingTests                   = 'Warning'
        enforceOrgBuildModesSettings           = $false
        enableCodeCopForTestApps               = $Settings.enableCodeCop
        enableUICopForTestApps                 = $Settings.enableUICop
        enablePerTenantExtensionCopForTestApps = $Settings.enablePerTenantExtensionCop
        enableAppSourceCopForTestApps          = $Settings.enableAppSourceCop
        customCodeCopsForTestApps              = $Settings.customCodeCops
        rulesetFileForTestApps                 = $Settings.rulesetFile
        obsoleteTagVersion                     = ''
        obsoleteTagPattern                     = ''
        createTranslations                     = $false
        translationLanguages                   = @()
        testTranslations                       = $false
        testTranslationRules                   = @()
    }

    $alpacaProperty = ([pscustomobject]$Settings).PSObject.Properties['alpaca']
    if ($alpacaProperty -and $null -ne $alpacaProperty.Value) {
        $alpacaSettings = [pscustomobject]$alpacaProperty.Value
        foreach ($keyValue in $defaultAlpacaSettings.GetEnumerator()) {
            if (-not $alpacaSettings.PSObject.Properties[$keyValue.Key]) {
                $alpacaSettings | Add-Member -NotePropertyName $keyValue.Key -NotePropertyValue $keyValue.Value
            }
        }
    }
    else {
        $alpacaSettings = [pscustomobject]$defaultAlpacaSettings
    }

    return $alpacaSettings
}
Export-ModuleMember -Function Get-AlpacaALGoSettings