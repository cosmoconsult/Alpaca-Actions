Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

$script:MagicHashMarkerTemplate = '<!-- alpaca-compiler-diagnostics-hash:{0}-->'

function Invoke-GhApiJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,
        [Parameter(Mandatory = $false)]
        [string] $JsonInput = '',
        [Parameter(Mandatory = $false)]
        [switch] $Paginate
    )
    Write-AlpacaDebug -Message "Invoke: gh $($Arguments -join ' ')"
    if ($Paginate) {
        $output = gh @Arguments --paginate --slurp 2>&1
    }
    elseif ([string]::IsNullOrWhiteSpace($JsonInput)) {
        $output = gh @Arguments --include 2>&1
    }
    else {
        $output = $JsonInput | gh @Arguments --include --input - 2>&1
    }
    $exitCode = $LASTEXITCODE
    if ($Paginate) {
        if ($exitCode -ne 0) {
            throw "gh $($Arguments -join ' ') --paginate --slurp failed: $(($output | Out-String).Trim())"
        }
        $pages = @($output | ConvertFrom-Json)
        return $pages | ForEach-Object { $_ }
    }

    $response = Get-GhApiResponse -Output $output
    $responseHeaderMessage = @(
        if (-not [string]::IsNullOrWhiteSpace($response.retryAfter)) { "Retry-After: $($response.retryAfter)." }
        if (-not [string]::IsNullOrWhiteSpace($response.rateLimitRemaining)) { "x-ratelimit-remaining: $($response.rateLimitRemaining)." }
        if (-not [string]::IsNullOrWhiteSpace($response.rateLimitReset)) { "x-ratelimit-reset: $($response.rateLimitReset)." }
    ) -join ' '
    Write-AlpacaDebug -Message "gh rate limit response headers: $responseHeaderMessage"
    if ($exitCode -ne 0) {
        throw "gh $($Arguments -join ' ') failed: $responseHeaderMessage $($response.body)"
    }

    if ([string]::IsNullOrWhiteSpace($response.body)) {
        return $null
    }

    return $response.body | ConvertFrom-Json
}

function Get-GhApiResponse {
    param(
        [Parameter(Mandatory = $false)]
        [object[]] $Output
    )

    $responseText = ($Output | Out-String).Trim()
    $responseParts = [regex]::Split($responseText, '\r?\n\r?\n', 2)
    $responseHeaders = $responseParts[0]
    $responseBody = if ($responseParts.Count -gt 1) { $responseParts[1] } else { '' }
    if ([string]::IsNullOrWhiteSpace($responseBody)) {
        $responseLines = @($responseText -split '\r?\n')
        $bodyStartIndex = -1
        for ($index = 0; $index -lt $responseLines.Count; $index++) {
            if ($responseLines[$index] -match '^\s*[\[{]') {
                $bodyStartIndex = $index
                break
            }
        }
        if ($bodyStartIndex -ge 0) {
            $responseHeaders = @($responseLines | Select-Object -First $bodyStartIndex) -join "`n"
            $responseBody = @($responseLines | Select-Object -Skip $bodyStartIndex) -join "`n"
        }
        else {
            $jsonStartMatch = [regex]::Match($responseText, '[\[{]')
            if ($jsonStartMatch.Success) {
                $responseHeaders = $responseText.Substring(0, $jsonStartMatch.Index).Trim()
                $responseBody = $responseText.Substring($jsonStartMatch.Index)
            }
        }
    }
    $retryAfterMatch = [regex]::Match($responseHeaders, '(?im)^Retry-After:\s*(?<value>.+?)\s*$')
    $rateLimitRemainingMatch = [regex]::Match($responseHeaders, '(?im)^x-ratelimit-remaining:\s*(?<value>.+?)\s*$')
    $rateLimitResetMatch = [regex]::Match($responseHeaders, '(?im)^x-ratelimit-reset:\s*(?<value>.+?)\s*$')
    return [pscustomobject]@{
        body               = $responseBody
        retryAfter         = if ($retryAfterMatch.Success) { $retryAfterMatch.Groups['value'].Value } else { '' }
        rateLimitRemaining = if ($rateLimitRemainingMatch.Success) { $rateLimitRemainingMatch.Groups['value'].Value } else { '' }
        rateLimitReset     = if ($rateLimitResetMatch.Success) { $rateLimitResetMatch.Groups['value'].Value } else { '' }
    }
}

function Resolve-ReviewToken {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Repository,
        [Parameter(Mandatory = $true)]
        [string] $GitHubToken,
        [Parameter(Mandatory = $false)]
        [string] $ReviewContextSecretName = '',
        [Parameter(Mandatory = $false)]
        [string] $ReviewContextSecretValue = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($ReviewContextSecretName)) {
        Write-AlpacaDebug -Message "ReviewContextSecretName is set to '$ReviewContextSecretName'. Attempting to use it for review token resolution."
        if ([string]::IsNullOrWhiteSpace($ReviewContextSecretValue)) {
            Write-AlpacaWarning -Message "ReviewContextSecretName '$ReviewContextSecretName' is set, but the secret was not found or is empty."
            return [pscustomobject]@{
                token       = $GitHubToken
                tokenSource = 'ghTokenWorkflow'
            }
        }

        Write-AlpacaDebug "Decoding ReviewContextSecretValue from Base64."
        $ReviewContextSecretValue = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ReviewContextSecretValue))
        $trimmedSecretValue = $ReviewContextSecretValue.Trim()
        if ($trimmedSecretValue.StartsWith('{')) {
            Write-AlpacaDebug -Message "ReviewContextSecretName '$ReviewContextSecretName' contains JSON. Attempting to parse as GitHub App credentials."
            try {
                $parsed = $trimmedSecretValue | ConvertFrom-Json -AsHashtable
            }
            catch {
                Write-AlpacaWarning -Message "ReviewContextSecretName '$ReviewContextSecretName' contains invalid JSON. Falling back to workflow token."
                return [pscustomobject]@{
                    token       = $GitHubToken
                    tokenSource = 'ghTokenWorkflow'
                }
            }

            if ($parsed.ContainsKey('token') -and -not [string]::IsNullOrWhiteSpace($parsed.token)) {
                Write-AlpacaDebug -Message "ReviewContextSecretName '$ReviewContextSecretName' contains a direct token. Using it for review token resolution."
                return [pscustomobject]@{
                    token       = "$($parsed.token)"
                    tokenSource = "ReviewContextSecretName:$ReviewContextSecretName"
                }
            }

            try {
                Write-AlpacaDebug -Message "ReviewContextSecretName '$ReviewContextSecretName' contains GitHub App credentials. Attempting to create a GitHub App access token."
                return [pscustomobject]@{
                    token       = Invoke-ALGoCommand -ScriptBlock { GetAccessToken -token $trimmedSecretValue -repository $Repository -permissions @{ "contents" = "read"; "pull_requests" = "write" } }
                    tokenSource = "ReviewContextSecretName:$ReviewContextSecretName"
                }
            }
            catch {
                Write-AlpacaWarning -Message "ReviewContextSecretName '$ReviewContextSecretName' could not be used as GitHub App credentials. Falling back to workflow token. $($_.Exception.Message)"
                return [pscustomobject]@{
                    token       = $GitHubToken
                    tokenSource = 'ghTokenWorkflow'
                }
            }
        }
        Write-AlpacaDebug -Message "ReviewContextSecretName '$ReviewContextSecretName' does not contain JSON. Using it as a direct token for review token resolution."
        return [pscustomobject]@{
            token       = $trimmedSecretValue
            tokenSource = "ReviewContextSecretName:$ReviewContextSecretName"
        }
    }

    Write-AlpacaDebug -Message "ReviewContextSecretName is not set. Using workflow token for review token resolution."
    return [pscustomobject]@{
        token       = $GitHubToken
        tokenSource = 'ghTokenWorkflow'
    }
}

function Resolve-FindingPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FindingPath,
        [Parameter(Mandatory = $true)]
        [string[]] $ChangedFiles
    )

    $normalizedFindingPath = ConvertTo-AlpacaNormalizedPath -Path $FindingPath
    $directMatch = $ChangedFiles | Where-Object { $_.Equals($normalizedFindingPath, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if ($directMatch) {
        return $directMatch
    }

    $suffixMatch = $ChangedFiles | Where-Object { $_.EndsWith("/$normalizedFindingPath", [System.StringComparison]::OrdinalIgnoreCase) -or $normalizedFindingPath.EndsWith("/$_", [System.StringComparison]::OrdinalIgnoreCase) }
    if ($suffixMatch.Count -eq 1) {
        return $suffixMatch[0]
    }

    return $null
}

function Get-AlpacaCompilerFindingsFromLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]] $Lines,
        [Parameter(Mandatory = $false)]
        [string] $RepositoryRoot = $env:GITHUB_WORKSPACE
    )

    $findingsByKey = @{}
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $finding = $null
        if ($line -match '^(?<file>.+?)\((?<line>\d+)(?:,(?<col>\d+))?\):\s*(?<severity>info|warning|error)\s+(?<ruleId>[A-Za-z]{2,}\d+):\s*(?<message>.+)$') {
            $severity = $matches['severity'].ToLowerInvariant()
            if ($severity -eq 'info') {
                continue
            }

            $finding = [ordered]@{
                severity = $severity
                filePath = ConvertTo-AlpacaNormalizedPath -Path $matches['file'] -RepositoryRoot $RepositoryRoot
                line     = [int] $matches['line']
                column   = if ($matches['col']) { [int] $matches['col'] } else { $null }
                ruleId   = $matches['ruleId'].ToUpperInvariant()
                message  = $matches['message'].Trim()
            }
        }
        elseif ($line -match '^::(?<severity>warning|error)\s+(?<params>[^:]*)::(?<message>.+)$') {
            $severity = $matches['severity'].ToLowerInvariant()
            $paramsRaw = $matches['params']
            $annotationMessage = $matches['message']
            $params = @{}
            foreach ($parameter in $paramsRaw -split ',') {
                if ($parameter -match '^(?<key>[^=]+)=(?<value>.*)$') {
                    $params[$matches['key'].Trim()] = $matches['value'].Trim()
                }
            }

            if (-not $params.ContainsKey('file') -or -not $params.ContainsKey('line')) {
                continue
            }

            $diagnosticMessage = $annotationMessage.Trim()
            $ruleId = ''
            if ($diagnosticMessage -match '^(?<ruleId>[A-Za-z]{2,}\d+)\s*(?<remaining>.*)$') {
                $ruleId = $matches['ruleId'].ToUpperInvariant()
                $diagnosticMessage = $matches['remaining'].Trim()
            }

            if ([string]::IsNullOrWhiteSpace($ruleId)) {
                continue
            }

            $finding = [ordered]@{
                severity = $severity
                filePath = ConvertTo-AlpacaNormalizedPath -Path $params.file -RepositoryRoot $RepositoryRoot
                line     = [int] $params.line
                column   = if ($params.ContainsKey('col')) { [int] $params.col } else { $null }
                ruleId   = $ruleId
                message  = $diagnosticMessage
            }
        }

        if ($null -eq $finding) {
            continue
        }

        $finding.hash = ('{0}|{1}|{2}|{3}' -f $finding.filePath, $finding.line, $finding.ruleId, $finding.message) | ConvertTo-Hash
        if (-not $findingsByKey.ContainsKey($finding.hash)) {
            $findingsByKey[$finding.hash] = [pscustomobject] $finding
        }
    }

    return @($findingsByKey.Values)
}

function Test-LineBelongsToPullRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,
        [Parameter(Mandatory = $true)]
        [int] $Line,
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.HashSet[string]] $PullRequestCommitIds
    )
    Write-AlpacaDebug -Message "Invoke: git blame -s --porcelain -L $Line,$Line -- $FilePath"
    $blameOutput = @(git blame -s --porcelain -L "$Line,$Line" -- "$FilePath" 2>$null)
    Write-AlpacaDebug -Message "Blame output for $FilePath line ${Line}: $($blameOutput[0])"
    if ($LASTEXITCODE -ne 0) {
        Write-AlpacaDebug -Message "Line $Line in '$FilePath' does not belong to the pull request because git blame failed with exit code $LASTEXITCODE."
        return $false
    }

    if ($blameOutput.Count -eq 0) {
        Write-AlpacaDebug -Message "Line $Line in '$FilePath' does not belong to the pull request because git blame returned no output."
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($blameOutput[0])) {
        Write-AlpacaDebug -Message "Line $Line in '$FilePath' does not belong to the pull request because git blame returned an empty header."
        return $false
    }

    $blameHeaderMatch = [regex]::Match($blameOutput[0], '^(?<commit>[0-9a-f]{40})\s')
    if ($blameHeaderMatch.Success) {
        $blameCommitId = $blameHeaderMatch.Groups['commit'].Value
        $belongsToPullRequest = $PullRequestCommitIds.Contains($blameCommitId)
        Write-AlpacaDebug -Message "Line $Line in '$FilePath' belongs to pull request: $belongsToPullRequest. Blame commit: $blameCommitId."
        return $belongsToPullRequest
    }

    Write-AlpacaDebug -Message "Line $Line in '$FilePath' does not belong to the pull request because git blame header could not be parsed: $($blameOutput[0])"
    return $false
}

#region GitCommandWrappers
function Invoke-GitFetchBaseRef {
    param(
        [Parameter(Mandatory = $true)]
        [string] $BaseRef
    )

    git fetch origin "$BaseRef" --quiet
}

function Get-GitChangedFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string] $BaseRef
    )

    git diff --merge-base "origin/$BaseRef" HEAD --name-only
}

function Get-GitMergeBase {
    param(
        [Parameter(Mandatory = $true)]
        [string] $BaseRef
    )

    return (git merge-base "origin/$BaseRef" HEAD).Trim()
}

function Get-GitCommitIds {
    param(
        [Parameter(Mandatory = $true)]
        [string] $MergeBase
    )

    git rev-list "$MergeBase..HEAD"
}
#endregion GitCommandWrappers

function New-ReviewCommentBody {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Finding
    )

    $severityIcon = Get-SeverityIcon -Severity $Finding.severity
    $codeDisplay = $Finding.ruleId
    $ruleUrl = Get-DiagnosticCodeUrl -RuleId $Finding.ruleId
    if (-not [string]::IsNullOrWhiteSpace($ruleUrl)) {
        $codeDisplay = "[$($Finding.ruleId)]($ruleUrl)"
    }
    return "{0} **{1} {2}**: {3}" -f $severityIcon, $Finding.severity, $codeDisplay, $Finding.message
}

function Get-SeverityIcon {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Severity
    )

    switch ($Severity) {
        'error' { return '❌' }
        'warning' { return '⚠️' }
        default { return '' }
    }
}

function Get-DiagnosticCodeUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string] $RuleId
    )

    switch -Regex ($RuleId) {
        '^AL(?<ruleId>\d{4})$' { return ('https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/diagnostics/diagnostic-al{0}' -f $matches['ruleId']) }
        '^AS(?<ruleId>\d{4})$' { return ('https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/analyzers/appsourcecop-as{0}' -f $matches['ruleId']) }
        '^AA(?<ruleId>\d{4})$' { return ('https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/analyzers/codecop-aa{0}' -f $matches['ruleId']) }
        '^PTE(?<ruleId>\d{4})$' { return ('https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/analyzers/pertenantextensioncop-pte{0}' -f $matches['ruleId']) }
        '^AW(?<ruleId>\d{4})$' { return ('https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/analyzers/uicop-aw{0}' -f $matches['ruleId']) }
        '^AC(?<ruleId>\d{4})$' { return ('https://alcops.dev/docs/analyzers/applicationcop/ac{0}' -f $matches['ruleId']) }
        '^DC(?<ruleId>\d{4})$' { return ('https://alcops.dev/docs/analyzers/documentationcop/dc{0}' -f $matches['ruleId']) }
        '^FC(?<ruleId>\d{4})$' { return ('https://alcops.dev/docs/analyzers/formattingcop/fc{0}' -f $matches['ruleId']) }
        '^LC(?<ruleId>\d{4})$' { return ('https://alcops.dev/docs/analyzers/lintercop/lc{0}' -f $matches['ruleId']) }
        '^PX(?<ruleId>\d{4})$' { return ('https://alcops.dev/docs/analyzers/platformcop/pc{0}' -f $matches['ruleId']) }
        '^TA(?<ruleId>\d{4})$' { return ('https://alcops.dev/docs/analyzers/testautomationcop/ta{0}' -f $matches['ruleId']) }
        default { return $null }
    }
}

function Invoke-GhReviewCreate {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Repository,
        [Parameter(Mandatory = $true)]
        [int] $PullRequestNumber,
        [Parameter(Mandatory = $true)]
        [string] $HeadSha,
        [Parameter(Mandatory = $true)]
        [object[]] $Comments,
        [Parameter(Mandatory = $true)]
        [string] $Body,
        [Parameter(Mandatory = $false)]
        [long[]] $ExistingReviewIds = @()
    )

    $payload = @{
        body      = $Body
        commit_id = $HeadSha
        event     = 'COMMENT'
        comments  = $Comments
    } | ConvertTo-Json -Depth 10

    Write-AlpacaDebug -Message "Creating compiler diagnostics review with $($Comments.Count) comments."
    try {
        return Invoke-GhApiJson -Arguments @('api', '--method', 'POST', "/repos/$Repository/pulls/$PullRequestNumber/reviews") -JsonInput $payload
    }
    catch {
        $createReviewError = $_
        if ($createReviewError.Exception.Message -notmatch '\bHTTP 502\b') {
            throw
        }

        Write-AlpacaDebug -Message "Review creation returned HTTP 502. Waiting 10 seconds before checking whether GitHub created the review."
        Start-Sleep -Seconds 10
        $reviews = @(Invoke-GhApiJson -Arguments @('api', "/repos/$Repository/pulls/$PullRequestNumber/reviews?per_page=100") -Paginate)
        $createdReview = $reviews | Where-Object { $_.id -notin $ExistingReviewIds -and $_.body -eq $Body -and $_.commit_id -eq $HeadSha } | Select-Object -Last 1
        if ($null -ne $createdReview) {
            Write-AlpacaDebug -Message "Found compiler diagnostics review $($createdReview.id) after the HTTP 502 response. Resuming."
            return $createdReview
        }

        throw $createReviewError
    }
}

function Invoke-GhCommentMinimize {
    param(
        [Parameter(Mandatory = $true)]
        [string] $SubjectNodeId
    )

    $query = 'mutation($subjectId: ID!) { minimizeComment(input: { subjectId: $subjectId, classifier: OUTDATED }) { minimizedComment { isMinimized minimizedReason } } }'
    Invoke-GhApiJson -Arguments @('api', 'graphql', '-f', "query=$query", '-f', "subjectId=$SubjectNodeId") | Out-Null
}

function ConvertTo-Hash {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string] $InputObject
    )

    process {
        $normalizedInput = "$($InputObject.ToLowerInvariant())"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedInput)
        $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
        return ([Convert]::ToHexString($hash)).Substring(0, 16).ToLowerInvariant()
    }
}

Export-ModuleMember -Function @(
    'Invoke-GhApiJson',
    'Get-GhApiResponse',
    'Resolve-ReviewToken',
    'Resolve-FindingPath',
    'Get-AlpacaCompilerFindingsFromLines',
    'Test-LineBelongsToPullRequest',
    'Invoke-GitFetchBaseRef',
    'Get-GitChangedFiles',
    'Get-GitMergeBase',
    'Get-GitCommitIds',
    'New-ReviewCommentBody',
    'Get-SeverityIcon',
    'Get-DiagnosticCodeUrl',
    'Invoke-GhReviewCreate',
    'Invoke-GhCommentMinimize',
    'ConvertTo-Hash'
)