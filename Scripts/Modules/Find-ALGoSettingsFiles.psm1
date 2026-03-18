function Find-ALGoSettingsFiles {
    <#
    .SYNOPSIS
        Finds all AL-Go settings JSON files in the workspace.

    .DESCRIPTION
        Searches for AL-Go settings files including:
        - .github/AL-Go-Settings.json
        - .github/AL-Go-TemplateProjectSettings.doNotEdit.json
        - .github/AL-Go-TemplateRepoSettings.doNotEdit.json
        - .AL-Go/*.settings.json (recursive)
        - .AL-Go/settings.json (recursive)
        - .github/*.settings.json

    .PARAMETER WorkspacePath
        The root path of the workspace to search. Defaults to $env:GITHUB_WORKSPACE.

    .EXAMPLE
        $files = Find-ALGoSettingsFiles
        Finds all AL-Go settings files in the current GitHub workspace.

    .EXAMPLE
        $files = Find-ALGoSettingsFiles -WorkspacePath "C:\MyRepo"
        Finds all AL-Go settings files in a specific path.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string] $WorkspacePath = $env:GITHUB_WORKSPACE
    )

    $jsonFilePaths = @()

    # Define files to check in .github directory
    $githubFiles = @(
        "AL-Go-Settings.json",
        "AL-Go-TemplateProjectSettings.doNotEdit.json",
        "AL-Go-TemplateRepoSettings.doNotEdit.json"
    )

    # Add specific files from .github directory
    foreach ($fileName in $githubFiles) {
        $filePath = Join-Path $WorkspacePath ".github" $fileName
        if (Test-Path $filePath) {
            $jsonFilePaths += $filePath
        }
    }
    
    # Add all .AL-Go/*.settings.json files from root and subdirectories
    $algoSettingsJsonFiles = Get-ChildItem -Path $WorkspacePath -Filter "*.settings.json" -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Directory.Name -eq ".AL-Go" }
    Write-AlpacaOutput "Found $($algoSettingsJsonFiles.Count) *.settings.json files in .AL-Go directories"
    if ($algoSettingsJsonFiles) {
        $jsonFilePaths += $algoSettingsJsonFiles | Select-Object -ExpandProperty FullName
    }
    
    # Add all .AL-Go/settings.json files from root and subdirectories
    $algoSettingsFiles = Get-ChildItem -Path $WorkspacePath -Filter "settings.json" -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Directory.Name -eq ".AL-Go" }
    Write-AlpacaOutput "Found $($algoSettingsFiles.Count) settings.json files in .AL-Go directories"
    if ($algoSettingsFiles) {
        $jsonFilePaths += $algoSettingsFiles | Select-Object -ExpandProperty FullName
    }
    
    # Add all *.settings.json files from .github directory
    $githubPath = Join-Path $WorkspacePath ".github"
    if (Test-Path $githubPath) {
        $githubSettingsFiles = Get-ChildItem -Path $githubPath -Filter "*.settings.json" -File -Force -ErrorAction SilentlyContinue
        if ($githubSettingsFiles) {
            $jsonFilePaths += $githubSettingsFiles | Select-Object -ExpandProperty FullName
        }
    }

    return $jsonFilePaths
}

Export-ModuleMember -Function Find-ALGoSettingsFiles
