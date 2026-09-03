[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Actor', Justification = 'Used inside script block')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'match', Justification = 'Is an Auto-Generated Parameter for the MatchEvaluator delegate')]
[CmdletBinding()]
param(
    [string] $Actor,
    [Parameter(HelpMessage = "Repository write token", Mandatory = $false)]
    [string] $Token,
    [Parameter(HelpMessage = "The target branch to update", Mandatory = $true)]
    [string] $Branch,
    [Parameter(HelpMessage = "Direct Commit?", Mandatory = $false)]
    [bool] $DirectCommit,
    [Parameter(HelpMessage = "Dry run mode skips clone and commit", Mandatory = $false)]
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot = $env:GITHUB_WORKSPACE
$startMarker = '<!-- AUTO-UPDATE-START -->'
$endMarker = '<!-- AUTO-UPDATE-END -->'

function CollectDataFromRepository {
    param([string]$RepoRoot)
    $result = @{Projects = @() }

    $repoSettings = Invoke-ALGoCommand -ScriptBlock { ReadSettings -buildMode '' -project '' -userName '' -branchName '' }
    $repoSettings = Invoke-ALGoCommand -ScriptBlock { ConvertTo-HashTable -object $repoSettings -recurse }
    $projects = @(Invoke-ALGoCommand -ScriptBlock { GetProjectsFromRepository -baseFolder $RepoRoot -projectsFromSettings $repoSettings.projects })
    Write-AlpacaDebug -Message "Found $($projects.Count) project directory(ies) in repository: $($projects | Out-String)"
    foreach ($project in $projects) {
        $projectDir = Join-Path -Path $RepoRoot -ChildPath $project
        Write-AlpacaDebug -Message "Collecting data from project directory: $($projectDir)"
        $projectHeadline = $project
        if ([string]::IsNullOrWhiteSpace($projectHeadline) -or $projectHeadline -eq '.') {
            $projectHeadline = Split-Path -Leaf ([System.IO.Path]::GetFullPath($RepoRoot))
        }

        $thisProject = @{
            Path     = $projectDir
            Headline = $projectHeadline
            Apps     = @()
        }
        $apps = GetSortedAppsForProject -Project $project -RepoRoot $RepoRoot
        foreach ($app in $apps) {
            Write-AlpacaDebug -Message "Collecting data for app: $($app.Name) ($($app.Id) )"
            $thisProject.Apps += $app
        }
        $result.Projects += $thisProject

    }
    return $result
}

function GetMarkdownSafeText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    return ($Text -replace '\|', '\|' -replace '(\r\n|\r|\n)', ' ').Trim()
}

function GetAppLogoPath {
    param(
        [string]$RepoRoot,
        [string]$RelativeFolder,
        [string]$Logo
    )

    $logoFile = if ([string]::IsNullOrWhiteSpace($Logo)) { 'logo.png' } else { $Logo.Trim() }

    if ($logoFile -match '^(?i)(https?://|data:)') {
        return $logoFile
    }

    $repoAbsolutePath = [System.IO.Path]::GetFullPath($RepoRoot)
    $candidateRelativePath = Join-Path $RelativeFolder $logoFile
    $candidateAbsolutePath = [System.IO.Path]::GetFullPath((Join-Path $repoAbsolutePath $candidateRelativePath))
    $normalizedRelativePath = [System.IO.Path]::GetRelativePath($repoAbsolutePath, $candidateAbsolutePath)

    return $normalizedRelativePath.Replace('\', '/')
}

function GetSortedAppsForProject {
    param(
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Project', Justification = 'Used inside script block')]
        [object]$Project,
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'RepoRoot', Justification = 'Used inside script block')]
        [string]$RepoRoot
    )
    $projectSettings = Invoke-ALGoCommand -ScriptBlock { ReadSettings -baseFolder $RepoRoot -project $Project }
    $projectSettings = Invoke-ALGoCommand -ScriptBlock { ConvertTo-HashTable -object $projectSettings -recurse }
    Invoke-ALGoCommand -ScriptBlock { ResolveProjectFolders -project $Project -baseFolder $RepoRoot -projectSettings ([ref] $projectSettings) }
    $apps = @($projectSettings.appFolders) + @($projectSettings.testFolders) + @($projectSettings.bcptTestFolders) | ForEach-Object {
        $appDir = $_
        $appRelativeDirectory = Join-Path -Path $Project -ChildPath $appDir
        $appJsonFile = Join-Path -Path $RepoRoot -ChildPath $appRelativeDirectory -AdditionalChildPath 'app.json'
        $appJson = Get-Content -LiteralPath $appJsonFile -Raw | ConvertFrom-Json

        $description = if (-not [string]::IsNullOrWhiteSpace($appJson.brief)) { [string]$appJson.brief } else { [string]$appJson.description }
        $relativeFolder = $appRelativeDirectory.Replace('\', '/')
        $logoPath = GetAppLogoPath -RepoRoot $RepoRoot -RelativeFolder $relativeFolder -Logo ([string]$appJson.logo)
        $kindInfo = switch ($true) {
            $($appDir -in $projectSettings.appFolders) { [pscustomobject]@{ Name = 'App'; Rank = 0 } }
            $($appDir -in $projectSettings.testFolders) { [pscustomobject]@{ Name = 'TestApp'; Rank = 1 } }
            $($appDir -in $projectSettings.bcptTestFolders) { [pscustomobject]@{ Name = 'BCPTTestApp'; Rank = 2 } }
            default { [pscustomobject]@{ Name = 'Unknown'; Rank = 99 } }
        }


        $appDependencies = @(
            $appJson.dependencies |
            ForEach-Object {
                [pscustomobject]@{
                    Id        = [string]$_.id
                    Publisher = [string]$_.publisher
                    Name      = [string]$_.name
                    Version   = [string]$_.version
                }
            }
        )

        [pscustomobject]@{
            Id             = [string]$appJson.id
            Name           = $appJson.name
            Publisher      = $appJson.publisher
            Description    = $description
            RelativeFolder = $relativeFolder -replace '^(?:\./)+'
            LogoPath       = $logoPath
            KindName       = $kindInfo.Name
            KindRank       = $kindInfo.Rank
            Application    = [string]$appJson.application
            HelpUrl        = [string]$appJson.help
            PrivacyUrl     = [string]$appJson.privacyStatement
            EulaUrl        = [string]$appJson.eula
            Dependencies   = $appDependencies
        }


    }
    return @($apps | Sort-Object -Property KindRank, Name)
}

function GetHeaderBlock {
    param(
        [string]$MainAppId,
        [object]$RepoData
    )
    $r = @()
    $r += '<!--'
    $r += 'This section is auto-generated by the Update README Workflow.'
    $r += '{0}/{1}/actions/workflows/AlpacaUpdateReadme.yaml' -f $env:GITHUB_SERVER_URL, $env:GITHUB_REPOSITORY
    $r += 'Do not edit this section manually except the MainAppId identifier. Any changes will be overwritten.'
    $r += '-->'

    $selectedApp = $RepoData.Projects.Apps | Where-Object { $_.Id -eq $MainAppId } | Select-Object -First 1
    if ($null -eq $selectedApp) {
        $selectedApp = $RepoData.Projects.Apps | Where-Object { $_.KindName -eq 'App' } | Select-Object -First 1
    }
    if ($null -eq $selectedApp) {
        return $r
    }

    $helpLink = if (-not [string]::IsNullOrWhiteSpace($selectedApp.HelpUrl)) { '<a href="{0}">Documentation</a>' -f $selectedApp.HelpUrl } else { $null }
    $privacyLink = if (-not [string]::IsNullOrWhiteSpace($selectedApp.PrivacyUrl)) { '<a href="{0}">Privacy Statement</a>' -f $selectedApp.PrivacyUrl } else { $null }
    $eulaLink = if (-not [string]::IsNullOrWhiteSpace($selectedApp.EulaUrl)) { '<a href="{0}">EULA</a>' -f $selectedApp.EulaUrl } else { $null }
    $links = @($helpLink, $privacyLink, $eulaLink) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $r += '<!--MainAppId:{0}-->' -f $selectedApp.Id
    $r += '<p align="center"><img src="{0}" height="80" alt="Logo of {1}" /></p>' -f $selectedApp.LogoPath, $selectedApp.Name
    $r += ''
    $r += '<h1 align="center">{0}</h1>' -f $selectedApp.Name
    $r += ''
    $r += '<p align="center">'
    $r += 'A Microsoft Dynamics 365 Business Central extension by <b>{0}</b>.' -f $selectedApp.Publisher
    $r += ''
    $r += ($links -join ' | ')
    $r += '</p>'
    $r += ''
    $r += '---'
    $r += ''

    return $r
}

function GetProjectsBlock {
    param(
        [object]$RepoData
    )

    $r = @()
    $r += '## Projects'
    $r += ''
    foreach ($project in $RepoData.Projects) {
        $r += "### $($project.Headline)"
        $r += ''
        $r += '| Name | Kind | Description | Folder |'
        $r += '| --- | --- | --- | --- |'
        foreach ($app in $project.Apps) {
            $safeName = GetMarkdownSafeText -Text $app.Name
            $safeKindName = GetMarkdownSafeText -Text $app.KindName
            $safeDescription = GetMarkdownSafeText -Text $app.Description
            $folderLink = "[$($app.RelativeFolder)]($($app.RelativeFolder))"
            $r += "| $safeName | $safeKindName | $safeDescription | $folderLink |"
        }
        $r += ''
    }
    return $r
}

function GetDependenciesBlock {
    param(
        [object]$RepoData
    )

    $appsToAnalyse = $RepoData.Projects.Apps | Where-Object { $_.KindName -eq 'App' }

    $dependencies = @()
    $dependencies += @{
        Publisher = 'Microsoft'
        Name      = 'Application'
        Version   = $appsToAnalyse | Select-Object -ExpandProperty Application | Sort-Object -Property @{ Expression = { [version]$_ } } -Bottom 1
    }
    $appsToAnalyse | ForEach-Object { $_ | Select-Object -ExpandProperty Dependencies } | Where-Object { $RepoData.Projects.Apps.id -notcontains $_.Id } | Group-Object -Property Id | ForEach-Object {
        $depId = $_.Name
        $depApps = $_.Group
        $highestVersionApp = $depApps | Sort-Object -Property @{ Expression = { [version]$_.Version }; Descending = $true } | Select-Object -First 1
        $dependencies += @{
            Publisher = $highestVersionApp.Publisher
            Name      = if (-not [string]::IsNullOrWhiteSpace($highestVersionApp.Name)) { $highestVersionApp.Name } else { $depId }
            Version   = $highestVersionApp.Version
        }
    }
    $r = @()
    $r += '## Dependencies'
    $r += ''
    $r += '| Publisher | Name | Version |'
    $r += '| --- | --- | --- |'
    foreach ($dependency in $dependencies | Sort-Object -Property Publisher, Name) {
        $safePublisher = GetMarkdownSafeText -Text $dependency.Publisher
        $safeName = GetMarkdownSafeText -Text $dependency.Name
        $safeVersion = GetMarkdownSafeText -Text $dependency.Version
        $r += "| $safePublisher | $safeName | $safeVersion |"
    }
    $r += ''
    return $r
}

function GetBuildStatusBlock {
    $par = @($env:GITHUB_SERVER_URL, $env:GITHUB_REPOSITORY)
    $ciBadge = '[![CI/CD]({0}/{1}/actions/workflows/CICD.yaml/badge.svg?branch=main)]({0}/{1}/actions/workflows/CICD.yaml)' -f $par
    $currentBadge = '[![Current]({0}/{1}/actions/workflows/Current.yaml/badge.svg?branch=main)]({0}/{1}/actions/workflows/Current.yaml)' -f $par
    $nextMinorBadge = '[![Next Minor]({0}/{1}/actions/workflows/NextMinor.yaml/badge.svg?branch=main)]({0}/{1}/actions/workflows/NextMinor.yaml)' -f $par
    $nextMajorBadge = '[![Next Major]({0}/{1}/actions/workflows/NextMajor.yaml/badge.svg?branch=main)]({0}/{1}/actions/workflows/NextMajor.yaml)' -f $par
    $r = @()
    $r += '## Build Status'
    $r += ''
    $r += '| CI | Current | Next Minor | Next Major |'
    $r += '|:-------:|:----------:|:----------:|:----------:|'
    $r += "| $ciBadge | $currentBadge | $nextMinorBadge | $nextMajorBadge |"
    $r += ''
    return $r
}

function InitAndReadReadme {
    param(
        [string]$ReadmePath
    )

    if (-not (Test-Path -LiteralPath $ReadmePath)) {
        $readmeDirectory = Split-Path -Parent $ReadmePath
        if (-not [string]::IsNullOrWhiteSpace($readmeDirectory) -and -not (Test-Path -LiteralPath $readmeDirectory)) {
            $null = New-Item -Path $readmeDirectory -ItemType Directory -Force
        }

        $null = New-Item -Path $ReadmePath -ItemType File -Force
        return ''
    }

    return Get-Content -LiteralPath $ReadmePath -Raw
}

# Import helpers only when needed for clone/commit flow.
if (-not $DryRun) {
    $helperBasePath = "..\..\_actions\microsoft\AL-Go-Actions\"
    $alGoActionsPath = Get-ChildItem -Path $helperBasePath -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($null -eq $alGoActionsPath) { throw "AL-Go-Actions directory not found." }
    . (Join-Path -Path $alGoActionsPath.FullName -ChildPath "AL-Go-Helper.ps1" -Resolve)

    if (-not $Token) {
        throw "A repository write token is needed to create a direct commit or pull request."
    }


    $env:GH_TOKEN = $Token

    $commitMessage = '[COSMO Alpaca] Update README'
    if ($DirectCommit) {
        $commitMessage += ' [skip ci]'
    }
    Write-AlpacaOutput "Check if a pull request already exists for branch $Branch with title '$commitMessage'"
    $existingPullRequest = (gh api --paginate "/repos/$($env:GITHUB_REPOSITORY)/pulls?base=$Branch" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" | ConvertFrom-Json) |
    Where-Object { $_.title -eq $commitMessage } |
    Select-Object -First 1
    if ($existingPullRequest) {
        $errorMsg = "A pull request already exists for branch ${Branch}: $($existingPullRequest.html_url)."
        Write-AlpacaError $errorMsg
        throw $errorMsg
    }

    Write-AlpacaOutput "Clone into a new folder"
    $serverUrl, $newBranch = Invoke-ALGoCommand -ScriptBlock { CloneIntoNewFolder -actor $Actor -token $Token -updateBranch $Branch -DirectCommit $DirectCommit -newBranchPrefix 'update-readme' }
    Invoke-ALGoCommand -ScriptBlock { Invoke-Git status }
}
else {
    Write-AlpacaNotice "DryRun enabled. Skipping token exchange, pull request checks, and repository cloning."
}

try {
    if ($DryRun) {
        $repoRoot = if ([string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE)) { (Get-Location).Path } else { $env:GITHUB_WORKSPACE }
    }
    else {
        $repoRoot = Get-Location
    }

    # Collect Data
    $repoData = CollectDataFromRepository -RepoRoot $repoRoot
    Write-AlpacaDebug -Message "Collected data from repository: $($repoData | ConvertTo-Json -Depth 5 -WarningAction SilentlyContinue)"

    if ($repoData.Projects.Count -eq 0) {
        Write-AlpacaNotice "Repository does not contain any AL-Go projects. No README.md update will be performed."
        return
    }

    if ($repoData.Projects.Apps.Count -eq 0) {
        Write-AlpacaNotice "Repository does not contain any AL-Go apps. No README.md update will be performed."
        return
    }

    # Read or Create README.md
    Write-AlpacaDebug "Read or create README.md"
    $readmePath = Join-Path -Path $repoRoot -ChildPath 'README.md'
    $readmeContent = InitAndReadReadme -ReadmePath $readmePath


    Write-AlpacaDebug "Ensure README.md contains the auto-update markers"
    $startMatches = [regex]::Matches($readmeContent, [regex]::Escape($startMarker))
    $endMatches = [regex]::Matches($readmeContent, [regex]::Escape($endMarker))
    if ($startMatches.Count -eq 0 -and $endMatches.Count -eq 0) {
        $readmeContent = "$startMarker`r`n$endMarker`r`n`r`n$readmeContent"
    }
    elseif ($startMatches.Count -ne 1 -or $endMatches.Count -ne 1 -or $startMatches[0].Index -ge $endMatches[0].Index) {
        throw 'README.md must contain exactly one ordered AUTO-UPDATE marker pair.'
    }


    # Read the MainAppId from the README.md if it exists <!--MainAppId:0000000-0000-0000-0000-000000000000-->
    Write-AlpacaDebug -Message "Read MainAppId from README.md if it exists"
    $mainAppIdPattern = '<!--MainAppId:([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})-->'
    $mainAppIdMatch = [regex]::Match($readmeContent, $mainAppIdPattern)
    $mainAppId = if ($mainAppIdMatch.Success) { $mainAppIdMatch.Groups[1].Value } else { $null }


    Write-AlpacaDebug -Message "Create new auto-generated content for README.md"
    $newAutoGeneratedContent = @()
    $newAutoGeneratedContent += GetHeaderBlock -MainAppId $mainAppId -RepoData $repoData
    $newAutoGeneratedContent += GetBuildStatusBlock
    $newAutoGeneratedContent += GetProjectsBlock -RepoData $repoData
    $newAutoGeneratedContent += GetDependenciesBlock -RepoData $repoData

    Write-AlpacaDebug -Message "New auto-generated content for README.md:`r`n$($newAutoGeneratedContent -join "`r`n")"

    #Write to file
    Write-AlpacaDebug -Message "Update README.md with new auto-generated content"
    $replacementContent = "$startMarker`r`n$($newAutoGeneratedContent -join "`r`n")`r`n$endMarker"
    $readmeContent = [regex]::Replace(
        $readmeContent,
        "(?s)$([regex]::Escape($startMarker)).*?$([regex]::Escape($endMarker))",
        [System.Text.RegularExpressions.MatchEvaluator] { param($Match) $replacementContent }
    )
    Set-Content -LiteralPath $readmePath -Value $readmeContent -Force -NoNewline

    # Print content of README.md for debugging purposes. reread file to ensure we have the latest content
    $finalReadmeContent = Get-Content -LiteralPath $readmePath -Raw
    Write-AlpacaDebug -Message "Final content of README.md:`r`n$finalReadmeContent"
}
catch {
    Write-AlpacaError -Message "An error occurred while updating the README.md: $($_.Exception.Message)"
    throw
}


if (-not $DryRun) {
    Write-AlpacaOutput "Commit and push changes"
    $committed = Invoke-ALGoCommand -ScriptBlock { CommitFromNewFolder -serverUrl $serverUrl -commitMessage $commitMessage -branch $newBranch -headBranch $Branch }
    if (-not $committed) {
        Write-AlpacaNotice "No README.md changes."
    }
}
else {
    Write-AlpacaNotice "DryRun enabled. Skipping commit and push."
}