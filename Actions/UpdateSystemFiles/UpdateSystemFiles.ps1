Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $Actor,
    [Parameter(HelpMessage = "Base64 encoded GhTokenWorkflow secret", Mandatory = $false)]
    [string] $Token,
    [Parameter(HelpMessage = "URL of the template repository (default is the template repository used to create the repository)", Mandatory = $false)]
    [string] $TemplateUrl = "",
    [Parameter(HelpMessage = "Set this input to true in order to download latest version of the template repository (else it will reuse the SHA from last update)", Mandatory = $true)]
    [bool] $DownloadLatest,
    [Parameter(HelpMessage = "Set the branch to update", Mandatory = $false)]
    [string] $UpdateBranch,
    [Parameter(HelpMessage = "Direct Commit?", Mandatory = $false)]
    [bool] $DirectCommit
)

if (-not $Token) {
    throw "The GhTokenWorkflow secret is needed. Read https://github.com/microsoft/AL-Go/blob/main/Scenarios/GhTokenWorkflow.md for more information."
}
else {
    # token comes from a secret, base 64 encoded
    $Token = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Token))
}

Write-Host "Download and Import AL-Go Helpers"
$helperFiles = @{  
    "AL-Go-Helper.ps1"                    = "https://raw.githubusercontent.com/microsoft/AL-Go/ab2f5319ed073c542e03914f8ae6c0fda029ee1e/Actions/AL-Go-Helper.ps1"
    "Github-Helper.psm1"                  = "https://raw.githubusercontent.com/microsoft/AL-Go/ab2f5319ed073c542e03914f8ae6c0fda029ee1e/Actions/Github-Helper.psm1"
    "CheckForUpdates.HelperFunctions.ps1" = "https://raw.githubusercontent.com/microsoft/AL-Go/ab2f5319ed073c542e03914f8ae6c0fda029ee1e/Actions/CheckForUpdates/CheckForUpdates.HelperFunctions.ps1"
    "settings.schema.json"                = "https://raw.githubusercontent.com/microsoft/AL-Go/ab2f5319ed073c542e03914f8ae6c0fda029ee1e/Actions/settings.schema.json"
}
foreach ($file in $helperFiles.Keys) {
    $url = $helperFiles[$file]
    $dest = Join-Path $PSScriptRoot $file
    try {
        Invoke-RestMethod -Uri $url -Headers @{ "Authorization" = "token $(gh auth token)" } -OutFile $dest -ErrorAction Stop
    }
    catch {
        throw "Failed to download ${file} from ${url}: " + $_.Exception.Message
    }
}
. (Join-Path $PSScriptRoot "AL-Go-Helper.ps1")
. (Join-Path $PSScriptRoot "CheckForUpdates.HelperFunctions.ps1")

if (-not $TemplateUrl.Contains('@')) {
    $TemplateUrl += "@main"
}
if ($TemplateUrl -notlike "https://*") {
    $TemplateUrl = "https://github.com/$TemplateUrl"
}
# Remove www part (if exists)
$TemplateUrl = $TemplateUrl -replace "^(https:\/\/)(www\.)(.*)$", '$1$3'

$repoSettings = ReadSettings -project '' -workflowName '' -userName '' -branchName '' | ConvertTo-HashTable -recurse
$templateSha = $repoSettings.templateSha
# If templateUrl has changed, download latest version of the template repository (ignore templateSha)
if ($repoSettings.templateUrl -ne $env:templateUrl -or $templateSha -eq '') {
    $DownloadLatest = $true
}

$templateFolder = DownloadTemplateRepository -token $Token -templateUrl $TemplateUrl -templateSha ([ref]$templateSha) -downloadLatest $DownloadLatest
Write-Host "Template Folder: $templateFolder"
$templateOwner = $TemplateUrl.Split('/')[3]
$templateInfo = "$templateOwner/$($TemplateUrl.Split('/')[4])"

try {
    # If a pull request already exists with the same REF, then exit
    $branchSHA = RunAndCheck git rev-list -n 1 $UpdateBranch '--'
    $commitMessage = "[$($UpdateBranch)@$($branchSHA.SubString(0,7))] Update COSMO Alpaca System Files from $templateInfo - $($templateSha.SubString(0,7)) [skip ci]"

    $env:GH_TOKEN = $Token
    $existingPullRequest = (gh api --paginate "/repos/$env:GITHUB_REPOSITORY/pulls?base=$UpdateBranch" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" | ConvertFrom-Json) | Where-Object { $_.title -eq $commitMessage } | Select-Object -First 1
    if ($existingPullRequest) {
        OutputWarning "Pull request already exists for $($commitMessage): $($existingPullRequest.html_url)."
        exit
    }

    $serverUrl, $branch = CloneIntoNewFolder -actor $Actor -token $Token -updateBranch $UpdateBranch -DirectCommit $DirectCommit -newBranchPrefix 'update-cosmo-alpaca-system-files'

    invoke-git status

    Write-Host "Updating Files..."
    $subFolder = (Get-ChildItem $templateFolder).Name
    $alpacaSource = Join-Path (Join-Path $templateFolder $subFolder) '.alpaca'
    $alpacaDest = Join-Path (Get-Location) '.alpaca'

    if (-Not (Test-Path $alpacaSource)) {
        OutputNotice -message "No COSMO Alpaca related files found in the template repository, nothing to update."
        exit 0
    }

    if (Test-Path $alpacaDest) {
        # Delete all files in destination except configs (*.json files)
        Get-ChildItem -Path $alpacaDest -Recurse -File -Exclude "*.json" -ErrorAction Stop | Remove-Item -Force -ErrorAction Stop
        # Then delete directories (from deepest to shallowest to avoid dependency issues)
        $dirsToRemove = Get-ChildItem -Path $alpacaDest -Recurse -Directory -ErrorAction Stop | Sort-Object -Property { $_.FullName.Length } -Descending
        foreach ($dir in $dirsToRemove) {
            # Only delete empty directories
            if (@(Get-ChildItem -Path $dir.FullName -ErrorAction Stop).Count -eq 0) {
                Remove-Item -Path $dir.FullName -Force -ErrorAction Stop
            }
        }

        # Copy new files from source to destination without overwriting existing configs (*.json files)
        $filesToCopy = Get-ChildItem -Path $alpacaSource -Recurse -File -Exclude "*.json" -ErrorAction Stop
        foreach ($file in $filesToCopy) {
            $destFile = Join-Path $alpacaDest $file.FullName.Substring($alpacaSource.Length + 1)
            # Ensure the destination directory exists
            $destDir = Split-Path $destFile -Parent
            if (-not (Test-Path -PathType Container $destDir)) {
                New-Item -Path $destDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            Copy-Item -Path $file.FullName -Destination $destFile -Force -ErrorAction Stop
        }
    }
    else {
        # Copy everything if destination does not exist
        Copy-Item -Path (Join-Path $alpacaSource "*") -Destination $alpacaDest -Recurse -Force -ErrorAction Stop
    }

    if (!(CommitFromNewFolder -serverUrl $serverUrl -commitMessage $commitMessage -branch $branch -headBranch $UpdateBranch)) {
        OutputNotice -message "No updates available for COSMO Alpaca."
    }
}
catch {
    if ($DirectCommit) {
        throw "Failed to update COSMO Alpaca System Files. Make sure that the personal access token, defined in the secret called GhTokenWorkflow, is not expired and it has permission to update workflows. Read https://github.com/microsoft/AL-Go/blob/main/Scenarios/GhTokenWorkflow.md for more information. (Error was $($_.Exception.Message))"
    }
    else {
        throw "Failed to create a pull-request to COSMO Alpaca System Files. Make sure that the personal access token, defined in the secret called GhTokenWorkflow, is not expired and it has permission to update workflows. Read https://github.com/microsoft/AL-Go/blob/main/Scenarios/GhTokenWorkflow.md for more information. (Error was $($_.Exception.Message))"
    }
}