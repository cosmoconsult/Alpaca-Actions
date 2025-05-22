Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "Base64 encoded GhTokenWorkflow secret", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "URL of the template repository (default is the template repository used to create the repository)", Mandatory = $false)]
    [string] $templateUrl = "",
    [Parameter(HelpMessage = "Set this input to true in order to download latest version of the template repository (else it will reuse the SHA from last update)", Mandatory = $true)]
    [bool] $downloadLatest,
    [Parameter(HelpMessage = "Set the branch to update", Mandatory = $false)]
    [string] $updateBranch,
    [Parameter(HelpMessage = "Direct Commit?", Mandatory = $false)]
    [bool] $directCommit
)

if (-not $token) {
    throw "The GhTokenWorkflow secret is needed. Read https://github.com/microsoft/AL-Go/blob/main/Scenarios/GhTokenWorkflow.md for more information."
}
else {
    # token comes from a secret, base 64 encoded
    $token = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($token))
    $env:GITHUB_TOKEN = $token
}
$headers = @{
    "Accept"        = "application/vnd.github+json"
    "Authorization" = "Bearer $token"
}

Write-Host "Download and Import AL-Go Helpers"
$helperFiles = @{  
    "AL-Go-Helper.ps1"                    = "https://raw.githubusercontent.com/freddydk/AL-Go/customize/Actions/AL-Go-Helper.ps1"
    "Github-Helper.psm1"                  = "https://raw.githubusercontent.com/freddydk/AL-Go/customize/Actions/Github-Helper.psm1"
    "CheckForUpdates.HelperFunctions.ps1" = "https://raw.githubusercontent.com/freddydk/AL-Go/customize/Actions/CheckForUpdates/CheckForUpdates.HelperFunctions.ps1"
    "settings.schema.json"                = "https://raw.githubusercontent.com/freddydk/AL-Go/customize/Actions/settings.schema.json"
}
foreach ($file in $helperFiles.Keys) {
    $url = $helperFiles[$file]
    $dest = Join-Path $PSScriptRoot $file
    try {
        Invoke-RestMethod -Uri $url -Headers $headers -OutFile $dest -ErrorAction Stop
    }
    catch {
        throw "Failed to download ${file} from ${url}: " + $_.Exception.Message
    }
}
. (Join-Path $PSScriptRoot "AL-Go-Helper.ps1")
. (Join-Path $PSScriptRoot "CheckForUpdates.HelperFunctions.ps1")

if (-not $templateUrl.Contains('@')) {
    $templateUrl += "@main"
}
if ($templateUrl -notlike "https://*") {
    $templateUrl = "https://github.com/$templateUrl"
}
# Remove www part (if exists)
$templateUrl = $templateUrl -replace "^(https:\/\/)(www\.)(.*)$", '$1$3'

$repoSettings = ReadSettings -project '' -workflowName '' -userName '' -branchName '' | ConvertTo-HashTable -recurse
$templateSha = $repoSettings.templateSha
# If templateUrl has changed, download latest version of the template repository (ignore templateSha)
if ($repoSettings.templateUrl -ne $env:templateUrl -or $templateSha -eq '') {
    $downloadLatest = $true
}

$templateFolder = DownloadTemplateRepository -headers $headers -templateUrl $templateUrl -templateSha ([ref]$templateSha) -downloadLatest $downloadLatest
Write-Host "Template Folder: $templateFolder"
$templateOwner = $templateUrl.Split('/')[3]
$templateInfo = "$templateOwner/$($templateUrl.Split('/')[4])"

try {
    # If a pull request already exists with the same REF, then exit
    $branchSHA = RunAndCheck git rev-list -n 1 $updateBranch '--'
    $commitMessage = "[$($updateBranch)@$($branchSHA.SubString(0,7))] Update COSMO Alpaca System Files from $templateInfo - $($templateSha.SubString(0,7)) [skip ci]"

    $existingPullRequest = (gh api --paginate "/repos/$env:GITHUB_REPOSITORY/pulls?base=$updateBranch" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" | ConvertFrom-Json) | Where-Object { $_.title -eq $commitMessage } | Select-Object -First 1
    if ($existingPullRequest) {
        OutputWarning "Pull request already exists for $($commitMessage): $($existingPullRequest.html_url)."
        exit
    }

    $serverUrl, $branch = CloneIntoNewFolder -actor $actor -token $token -updateBranch $updateBranch -DirectCommit $directCommit -newBranchPrefix 'update-cosmo-alpaca-system-files'

    invoke-git status

    Write-Host "Updating Files..."
    $subFolder = (Get-ChildItem $templateFolder).Name
    $alpacaSource = Join-Path (Join-Path $templateFolder $subFolder) '.alpaca'
    $alpacaDest = Join-Path $ENV:GITHUB_WORKSPACE '.alpaca'

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

        Write-Host "Updating Git index..."
        # Remove files that are tracked but don't exist anymore (workaround as `git add` in `CommitFromNewFolder` doesn't recognize deleted files)
        $existingAlpacaFiles = Get-ChildItem -Path $alpacaDest -Recurse -File | ForEach-Object { $_.FullName }
        $trackedAlpacaFiles = invoke-git -returnValue ls-files '.alpaca'
        foreach ($trackedFile in $trackedAlpacaFiles) {
            $fullPath = Join-Path $ENV:GITHUB_WORKSPACE $trackedFile
            if (-not ($existingAlpacaFiles -contains $fullPath)) {
                invoke-git rm $trackedFile --quiet
            }
        }
    }
    else {
        # Copy everything if destination does not exist
        Copy-Item -Path (Join-Path $alpacaSource "*") -Destination $alpacaDest -Recurse -Force -ErrorAction Stop
    }

    if (!(CommitFromNewFolder -serverUrl $serverUrl -commitMessage $commitMessage -branch $branch -headBranch $updateBranch)) {
        OutputNotice -message "No updates available for COSMO Alpaca."
    }
}
catch {
    if ($directCommit) {
        throw "Failed to update COSMO Alpaca System Files. Make sure that the personal access token, defined in the secret called GhTokenWorkflow, is not expired and it has permission to update workflows. Read https://github.com/microsoft/AL-Go/blob/main/Scenarios/GhTokenWorkflow.md for more information. (Error was $($_.Exception.Message))"
    }
    else {
        throw "Failed to create a pull-request to COSMO Alpaca System Files. Make sure that the personal access token, defined in the secret called GhTokenWorkflow, is not expired and it has permission to update workflows. Read https://github.com/microsoft/AL-Go/blob/main/Scenarios/GhTokenWorkflow.md for more information. (Error was $($_.Exception.Message))"
    }
}