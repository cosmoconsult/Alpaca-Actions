param(
    [Parameter(Mandatory = $true)]
    [string] $Repository,
    [Parameter(Mandatory = $true)]
    [int] $PullRequestNumber,
    [Parameter(Mandatory = $true)]
    [string] $BaseRef,
    [Parameter(Mandatory = $true)]
    [string] $HeadSha,
    [Parameter(Mandatory = $true)]
    [string] $BuildOutputPath,
    [Parameter(Mandatory = $true)]
    [string] $GitHubToken,
    [Parameter(Mandatory = $false)]
    [string] $ReviewContextSecretName = '',
    [Parameter(Mandatory = $false)]
    [string] $ReviewContextSecretValue = ''
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking
$helperModuleName = 'ReportCompilerDiagnosticsAsReviewComments'
if (-not (Get-Module -Name $helperModuleName)) {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "$helperModuleName.psm1" -Resolve) -DisableNameChecking
}

$magicReviewMarker = '<!-- alpaca-compiler-diagnostics-review -->'
$magicHashMarkerTemplate = '<!-- alpaca-compiler-diagnostics-hash:{0}-->'
$maxNumberOfReviewComments = 50

Write-AlpacaGroupStart "Resolving review token"
try {
    $reviewTokenResolution = Resolve-ReviewToken -Repository $Repository -GitHubToken $GitHubToken -ReviewContextSecretName $ReviewContextSecretName -ReviewContextSecretValue $ReviewContextSecretValue

    $reviewToken = "$($reviewTokenResolution.token)"
    if ([string]::IsNullOrWhiteSpace($reviewToken)) {
        Write-AlpacaWarning -Message "Skipping compiler diagnostics review comments because no usable review token is available."
        exit 0
    }

    Write-AlpacaOutput -Message "Review API token source: $($reviewTokenResolution.tokenSource)"
    $env:GH_TOKEN = $reviewToken

    #Validating Token by attempting to access the pull request API
    try {
        $null = Invoke-GhApiJson -Arguments @('api', "/repos/$Repository/pulls/$PullRequestNumber")
    }
    catch {
        $warningMessage = "Cannot access pull request API with the selected token. $($_.Exception.Message)"
        if ($reviewTokenResolution.tokenSource -eq 'ghTokenWorkflow') {
            # TODO: Remove this warning note once ghTokenWorkflow is supported for compiler diagnostics review comments.
            $warningMessage += " Additional note: using ghTokenWorkflow for compiler diagnostics review comments is currently not supported. Use a GitHub App via the alpaca.ReviewContextSecretName setting."
        }
        Write-AlpacaWarning -Message $warningMessage
        exit 0
    }
}
finally {
    Write-AlpacaGroupEnd
}

#Fetch for later usage with diff, merge-base and rev-list
Invoke-GitFetchBaseRef -BaseRef $BaseRef

#region CollectBuildOutput
$buildOutputFiles = @(Get-ChildItem -Path $BuildOutputPath -Filter 'BuildOutput.txt' -File -Recurse -ErrorAction SilentlyContinue)
Write-AlpacaGroupStart "Collecting build output files"
try {
    if ($buildOutputFiles.Count -eq 0) {
        Write-AlpacaOutput "No BuildOutput.txt files found in '$BuildOutputPath'. Nothing to report."
        exit 0
    }
    Write-AlpacaOutput -Message "Found $($buildOutputFiles.Count) build output file(s)."

    $allLines = @()
    foreach ($buildOutputFile in $buildOutputFiles) {
        Write-AlpacaDebug -Message "Processing build output file: $($buildOutputFile.FullName)"
        $allLines += Get-Content -Path $buildOutputFile.FullName
    }

    if (Get-AlpacaIsDebugMode) {
        Write-AlpacaGroupStart "Build Output:"
        foreach ($line in $allLines) {
            Write-AlpacaDebug "    $line"
        }
        Write-AlpacaGroupEnd
    }

    if ($allLines.Count -eq 0) {
        Write-AlpacaDebug "No lines found in build output."
    }
}
finally {
    Write-AlpacaGroupEnd
}

#endregion

Write-AlpacaOutput -Message "Collecting included files."
$changedFiles = @(Get-GitChangedFiles -BaseRef $BaseRef | ForEach-Object { ConvertTo-AlpacaNormalizedPath -Path $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
if ($changedFiles.Count -eq 0) {
    Write-AlpacaOutput -Message "No changed files detected for the pull request."
    exit 0
}
Write-AlpacaOutput -Message "Changed files detected for the pull request: $($changedFiles.Count)"

Write-AlpacaOutput -Message "Collecting included commit ids."
$mergeBase = Get-GitMergeBase -BaseRef $BaseRef
$pullRequestCommitIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($commitId in (Get-GitCommitIds -MergeBase $mergeBase | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    $pullRequestCommitIds.Add($commitId.Trim()) | Out-Null
}
Write-AlpacaOutput -Message "Collected commit ids for the pull request: $($pullRequestCommitIds.Count)"

Write-AlpacaOutput -Message "Filter errors and warning from the build output."
$allFindings = @(Get-AlpacaCompilerFindingsFromLines -Lines $allLines -RepositoryRoot $env:GITHUB_WORKSPACE)
if ($allFindings.Count -eq 0) {
    Write-AlpacaOutput -Message "No compiler warnings or errors found."
}
Write-AlpacaOutput -Message "Collected all compiler findings from the build output: $($allFindings.Count)"

Write-AlpacaOutput -Message "Filter errors and warnings to files and commit ids in the pull request."
$relevantFindings = @()
foreach ($finding in $allFindings) {
    if (Get-AlpacaIsDebugMode) {
        Write-AlpacaGroupStart "Processing finding: $($finding | ConvertTo-AlpacaOutputString)"
    }
    try {
        $resolvedPath = Resolve-FindingPath -FindingPath $finding.filePath -ChangedFiles $changedFiles
        if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
            continue
        }

        $finding.filePath = $resolvedPath
        $finding.hash = ('{0}|{1}|{2}|{3}' -f $finding.filePath, $finding.line, $finding.ruleId, $finding.message) | ConvertTo-Hash

        if ($finding.severity -eq 'warning') {
            if (-not (Test-LineBelongsToPullRequest -FilePath $finding.filePath -Line $finding.line -PullRequestCommitIds $pullRequestCommitIds)) {
                continue
            }
        }
        Write-AlpacaDebug -Message "Adding relevant finding."
        if ($relevantFindings.hash -notcontains $finding.hash) {
            Write-AlpacaDebug -Message "Finding with hash $($finding.hash) is not yet in relevantFindings."
            $relevantFindings += $finding
        }
    }
    finally {
        if (Get-AlpacaIsDebugMode) {
            Write-AlpacaGroupEnd
        }
    }
}
Write-AlpacaOutput -Message "Filtered down to $($relevantFindings.Count) relevant findings."

Write-AlpacaOutput -Message "Sorting findings."
$relevantFindings = $relevantFindings | Sort-Object -Property severity, ruleId, filePath, line, message

try {
    $NewReviewHash = $relevantFindings | Select-Object -ExpandProperty hash | Sort-Object | Join-String -Separator ',' | ConvertTo-Hash
    $commentFindings = @($relevantFindings | Select-Object -First $maxNumberOfReviewComments) # will be created as review comments
    $overflowFindings = @($relevantFindings | Select-Object -Skip $maxNumberOfReviewComments) # will be included in the review body but not as individual comments

    Write-AlpacaOutput -Message "Prepare Review Body"
    $reviewBodyLines = @("Code analyzers identified $($relevantFindings.Count) findings that we were able to trace back to this change.")
    if ($overflowFindings.Count -gt 0) {
        $reviewBodyLines += ''
        $reviewBodyLines += "The first $maxNumberOfReviewComments diagnostics are attached as comments. The remaining $($overflowFindings.Count) diagnostics are:"
        $reviewBodyLines += ''
        foreach ($findingGroup in ($overflowFindings | Group-Object -Property severity, ruleId | Sort-Object Name)) {
            $finding = $findingGroup.Group[0]
            $codeUrl = Get-DiagnosticCodeUrl -RuleId $finding.ruleId
            $codeDisplay = [System.Net.WebUtility]::HtmlEncode($finding.ruleId)
            if (-not [string]::IsNullOrWhiteSpace($codeUrl)) {
                $codeDisplay = "<a href=`"$codeUrl`">$codeDisplay</a>"
            }
            $reviewBodyLines += '<details>'
            $reviewBodyLines += "<summary><b>$($finding.severity) $codeDisplay</b> ($($findingGroup.Group.Count) findings)</summary>"
            $reviewBodyLines += '<ul>'
            foreach ($groupedFinding in $findingGroup.Group) {
                $filePathBytes = [System.Text.Encoding]::UTF8.GetBytes($groupedFinding.filePath)
                $fileDiffHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($filePathBytes)).ToLowerInvariant()
                $fileUrl = '{0}/{1}/pull/{2}/files/{3}#diff-{4}' -f $env:GITHUB_SERVER_URL, $Repository, $PullRequestNumber, $HeadSha, $fileDiffHash
                $reviewBodyLines += '<li><a href="{0}"><code>{1}</code></a>: {2}</li>' -f $fileUrl, ([System.Net.WebUtility]::HtmlEncode("$($groupedFinding.filePath):$($groupedFinding.line)")), ([System.Net.WebUtility]::HtmlEncode($groupedFinding.message))
            }
            $reviewBodyLines += '</ul>'
            $reviewBodyLines += '</details>'
            $reviewBodyLines += ''
        }
    }
    $reviewBodyLines += ''
    $reviewBodyLines += $magicHashMarkerTemplate -f "$NewReviewHash"
    $reviewBodyLines += $magicReviewMarker
    $reviewBody = $reviewBodyLines -join "`n"

    Write-AlpacaOutput -Message "Prepare Review Comments"
    $comments = @($commentFindings | ForEach-Object {
            $comment = @{
                body = New-ReviewCommentBody -Finding $_
                path = $_.filePath
            }
            if ($_.severity -eq 'error') {
                $comment.subject_type = 'file'
            }
            else {
                $comment.line = $_.line
                $comment.side = 'RIGHT'
            }
            $comment
        })

    Write-AlpacaOutput -Message "Fetched existing reviews for pull request $PullRequestNumber."
    $reviews = @(Invoke-GhApiJson -Arguments @('api', "/repos/$Repository/pulls/$PullRequestNumber/reviews?per_page=100") -Paginate)
    Write-AlpacaDebug -Message "Fetched $($reviews.Count) reviews for pull request $PullRequestNumber."
    $previousReview = $reviews | Where-Object { $_.body -match [regex]::Escape($magicReviewMarker) } | Select-Object -Last 1
    Write-AlpacaOutput -Message "Found existing automatic review: $($previousReview.html_url)"
    $existingReviewComments = @()
    $reviewMatches = $false
    if ($null -ne $previousReview) {
        $previousReviewHashMatch = [regex]::Match($previousReview.body, ("(?i)$magicHashMarkerTemplate" -f '(?<hash>[a-f0-9]{16})'))
        $previousReviewHash = if ($previousReviewHashMatch.Success) { $previousReviewHashMatch.Groups['hash'].Value } else { '' }
        Write-AlpacaDebug -Message "Existing review hash: $previousReviewHash"
        Write-AlpacaDebug -Message "Expected review hash: $NewReviewHash"
        $reviewMatches = $previousReviewHash.Equals($NewReviewHash, [System.StringComparison]::OrdinalIgnoreCase)
        Write-AlpacaDebug -Message "Review matches: $reviewMatches"
    }

    if (-not $reviewMatches) {
        if ($relevantFindings.Count -gt 0) {
            Write-AlpacaOutput -Message "Creating compiler diagnostics review with $($comments.Count) comments."
            Invoke-GhReviewCreate -Repository $Repository -PullRequestNumber $PullRequestNumber -HeadSha $HeadSha -Comments $comments -Body $reviewBody -ExistingReviewIds @($reviews.id) | Out-Null
        }

        if ($null -ne $previousReview) {
            Write-AlpacaDebug -Message "Fetching comments for compiler diagnostics review $($previousReview.id)."
            $existingReviewComments = @(Invoke-GhApiJson -Arguments @('api', "/repos/$Repository/pulls/$PullRequestNumber/reviews/$($previousReview.id)/comments?per_page=100"))
            Write-AlpacaOutput -Message "Removing $($existingReviewComments.Count) comments from previous compiler diagnostics review."
            foreach ($existingReviewComment in $existingReviewComments) {
                Invoke-GhApiJson -Arguments @('api', '--method', 'DELETE', "/repos/$Repository/pulls/comments/$($existingReviewComment.id)") | Out-Null
            }

            Write-AlpacaOutput -Message "Hiding submitted compiler diagnostics review $($previousReview.id) as outdated."
            Invoke-GhCommentMinimize -SubjectNodeId $previousReview.node_id
        }
    }
    else {
        Write-AlpacaOutput -Message "Existing compiler diagnostics review and comments match. No changes are required."
    }
}
catch {
    if ($_.Exception.Message -match 'Resource not accessible by integration|403') {
        Write-AlpacaWarning -Message "The selected review token does not have permission to manage pull request review comments. Ensure selected Token ghTokenWorkflow has sufficient rights or configure alpaca.ReviewContextSecretName with a PAT or GitHub App secret. $($_.Exception.Message)"
        try {
            Write-AlpacaDebug -Message "Fetching rate limits for the selected review token."
            $rateLimitStatus = Invoke-GhApiJson -Arguments @('api', '/rate_limit')
            foreach ($resourceProperty in $rateLimitStatus.resources.PSObject.Properties) {
                $resource = $resourceProperty.Value
                $resetUtc = [DateTimeOffset]::FromUnixTimeSeconds([long]$resource.reset).UtcDateTime.ToString('o')
                Write-AlpacaDebug -Message "Rate limit '$($resourceProperty.Name)': limit=$($resource.limit), used=$($resource.used), remaining=$($resource.remaining), reset=$($resource.reset) ($resetUtc)."
            }
        }
        catch {
            Write-AlpacaDebug -Message "Failed to fetch rate limits: $($_.Exception.Message)"
        }
        exit 0
    }
    throw
}

Write-AlpacaOutput -Message "Compiler diagnostics comment synchronization completed. Relevant findings: $($relevantFindings.Count)."
