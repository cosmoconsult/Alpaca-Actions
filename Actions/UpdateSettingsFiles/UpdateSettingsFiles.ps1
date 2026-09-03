[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Actor', Justification = 'Used inside script block')]
param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $Actor,
    [Parameter(HelpMessage = "Base64 encoded GhTokenWorkflow secret", Mandatory = $false)]
    [string] $Token,
    [Parameter(HelpMessage = "The target repository to update", Mandatory = $true)]
    [string] $Repo,
    [Parameter(HelpMessage = "The target branch to update", Mandatory = $true)]
    [string] $Branch,
    [Parameter(HelpMessage = "Direct Commit?", Mandatory = $false)]
    [bool] $DirectCommit,
    [Parameter(HelpMessage = "Only check if settings are in sync", Mandatory = $false)]
    [bool] $DryRun
)

# Import helper functions (includes Alpaca module and AL-Go Helper imports)
. (Join-Path -Path $PSScriptRoot -ChildPath "UpdateSettingsFiles.HelperFunctions.ps1")

Write-AlpacaOutput "Get AL-Go Settings"
$settings = $env:Settings | ConvertFrom-Json
Write-AlpacaDebug "AL-Go settings:`n$($settings | ConvertTo-Json -Depth 10)"

Write-AlpacaOutput "Get AL-Go Alpaca Settings"
$alpacaSettings = Get-AlpacaALGoSettings -Settings $settings
Write-AlpacaDebug "AL-Go Alpaca settings:`n$($alpacaSettings | ConvertTo-Json -Depth 10)"

if (-not $dryRun -and -not $Token) {
    throw "The GhTokenWorkflow secret is needed. Read https://github.com/microsoft/AL-Go/blob/main/Scenarios/GhTokenWorkflow.md for more information."
}

# Step 1: Read AL-Go Settings from environment variables and files

$alGoSettingsObjects = @(Get-ALGoSettingsObjects -ALGoOrgSettingsJson "$($env:ALGoOrgSettings)" -ALGoRepoSettingsJson "$($env:ALGoRepoSettings)")

# Step 2: Update AL-Go Settings with inherited organization-level conditional settings

Update-ALGoSettingsObjectsWithOrgConditionalSettings -AlGoSettingsObjects $alGoSettingsObjects -Repository $Repo -EnforceOrgBuildModesSettings $alpacaSettings.enforceOrgBuildModesSettings

# Step 3: Write updated AL-Go Settings back to their source files

# Check if any AL-Go Settings objects were updated
$updatedAlGoSettingsObjects = @($alGoSettingsObjects | Where-Object { $_.Updated -and -not $_.Immutable })
if (-not $updatedAlGoSettingsObjects) {
    Write-AlpacaNotice "No updates for AL-Go Settings files."
    return
}

if ($DryRun) {
    # If DryRun is enabled, throw an error to indicate that the AL-Go Settings files need to be updated
    $errorLines = @("AL-Go Settings files need to be updated:")
    foreach ($alGoSettingsObject in $updatedAlGoSettingsObjects) {
        $errorLines += "- $($alGoSettingsObject.Source)"
        foreach ($update in $alGoSettingsObject.Updates) {
            $errorLines += "  - $update"
        }
    }
    $errorLines += "Run the workflow 'COSMO Alpaca - Update Settings Files' or 'Update AL-Go System Files' to resolve."
    $errorMsg = $errorLines -join "`n"
    Write-AlpacaError $errorMsg
    throw $errorMsg
}

Write-AlpacaOutput "Get a write access token for the repository $Repo"
$Token = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Token))
$repoWriteToken = Invoke-ALGoCommand -ScriptBlock { GetAccessToken -token $Token -repository $Repo -permissions @{"contents" = "write"; "pull_requests" = "write" } }
$env:GH_TOKEN = $repoWriteToken

$commitMessage = "[COSMO Alpaca] Update AL-Go Settings Files"

$Branch = $Branch.Replace("refs/heads/", "")
Write-AlpacaOutput "Check if a pull request already exists for branch $Branch with title '$commitMessage'"
$existingPullRequest = (gh api --paginate "/repos/$Repo/pulls?base=$Branch" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" | ConvertFrom-Json) |
Where-Object { $_.title -eq $commitMessage } |
Select-Object -First 1
if ($existingPullRequest) {
    $errorMsg = "A pull request already exists for branch ${Branch}: $($existingPullRequest.html_url)."
    Write-AlpacaError $errorMsg
    throw $errorMsg
}

try {
    Write-AlpacaGroupStart "Update AL-Go Settings Files in repository $Repo on branch $Branch (direct commit: $DirectCommit)"

    Write-AlpacaOutput "Clone into a new folder"
    $serverUrl, $newBranch = Invoke-ALGoCommand -ScriptBlock { CloneIntoNewFolder -actor $Actor -token $repoWriteToken -updateBranch $Branch -DirectCommit $DirectCommit -newBranchPrefix 'update-al-go-settings-files' }
    Invoke-ALGoCommand -ScriptBlock { invoke-git status }

    Write-AlpacaGroupStart "Update AL-Go Settings Files"
    foreach ($updatedAlGoSettingsObject in $updatedAlGoSettingsObjects) {
        Write-AlpacaOutput "Write AL-Go Settings File: $($updatedAlGoSettingsObject.Source)"
        Write-ALGoSettingsFile -Settings $updatedAlGoSettingsObject.Settings -Path $updatedAlGoSettingsObject.Source
    }
    Write-AlpacaGroupEnd

    Write-AlpacaOutput "Commit and push changes"
    $committed = Invoke-ALGoCommand -ScriptBlock { CommitFromNewFolder -serverUrl $serverUrl -commitMessage $commitMessage -branch $newBranch -headBranch $Branch }
    if (-not $committed) {
        Write-AlpacaNotice "No AL-Go Settings files changed."
    }
}
catch {
    if ($DirectCommit) {
        throw "Failed to update AL-Go Settings Files. Make sure that the personal access token, defined in the secret called GhTokenWorkflow, is not expired and it has permission to update the repository. Read https://github.com/microsoft/AL-Go/blob/main/Scenarios/GhTokenWorkflow.md for more information. (Error was $($_.Exception.Message))"
    }
    else {
        throw "Failed to create a pull-request to update the AL-Go Settings Files. Make sure that the personal access token, defined in the secret called GhTokenWorkflow, is not expired and it has permission to update the repository. Read https://github.com/microsoft/AL-Go/blob/main/Scenarios/GhTokenWorkflow.md for more information. (Error was $($_.Exception.Message))"
    }
}
finally {
    Write-AlpacaGroupEnd
}
