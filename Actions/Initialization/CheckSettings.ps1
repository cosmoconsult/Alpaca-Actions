param (
    [Parameter(HelpMessage = "GitHub repository")]
    [string] $Repo = $env:GITHUB_REPOSITORY,
    [Parameter(HelpMessage = "GitHub ref")]
    [string] $Ref = $env:GITHUB_SHA,
    [Parameter(HelpMessage = "GitHub workflow")]
    [string] $Workflow = $env:GITHUB_WORKFLOW
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

function Get-GitHubApiFileContentUrl {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Repo,
        [Parameter(Mandatory = $true)]
        [string] $FilePath,
        [Parameter(Mandatory = $true)]
        [string] $Ref
    )
    $segments = "repos/$Repo/contents/$FilePath" -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }
    $query = "?ref=$([System.Uri]::EscapeDataString($Ref))"
    return "$($segments -join '/')$query"
}

# Check 1: Deprecated config file
$deprecatedConfigFile = '.alpaca/alpaca.json'
$output = gh api (Get-GitHubApiFileContentUrl -Repo $Repo -FilePath $deprecatedConfigFile -Ref $Ref) --silent 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-AlpacaWarning -Message "The configuration file '$($deprecatedConfigFile)' is deprecated.`nThis will become an error in the future.`n`nPlease migrate to AL-Go settings.`nSee: https://docs.cosmoconsult.com/en-us/cloud-service/alpaca/github/setup-al-go-settings.html#migrating-from-alpacajson"
} elseif ($output -notmatch '404|Not Found') {
    Write-AlpacaWarning -Message "Could not check '$($deprecatedConfigFile)': $output"
}

# Check 2: Expected workflow settings (only for relevant workflows)
$expectedWorkflowSettings = @{
    'Test Current'   = @{
        artifact = '////latest'
        cacheImageName = ''
        versioningStrategy = 15
    }
    'Test Next Minor' = @{
        artifact = '////nextminor'
        cacheImageName = ''
        versioningStrategy = 15
    }
    'Test Next Major' = @{
        artifact = '////nextmajor'
        cacheImageName = ''
        versioningStrategy = 15
    }
}.GetEnumerator() | Where-Object { $_.Key -eq $Workflow } | Select-Object -First 1 -ExpandProperty Value

if ($expectedWorkflowSettings) {
    $settingsFile = ".github/$($Workflow).settings.json"
    $output = gh api (Get-GitHubApiFileContentUrl -Repo $Repo -FilePath $settingsFile -Ref $Ref) 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($output -match '404|Not Found') {
            Write-AlpacaWarning -Message "Settings file '$($settingsFile)' is missing."
        } else {
            Write-AlpacaWarning -Message "Could not check '$($settingsFile)': $output"
        }
    } else {
        try {
            $rawContent = ($output | ConvertFrom-Json).content -replace '\s', ''
            $settings = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($rawContent)) | ConvertFrom-Json

            foreach ($property in $expectedWorkflowSettings.GetEnumerator()) {
                if ($settings | Get-Member -Name $property.Key -MemberType NoteProperty) {
                    if ($settings.$($property.Key) -ne $property.Value) {
                        Write-AlpacaWarning -Message "Settings file '$($settingsFile)': Property '$($property.Key)' has unexpected value '$($settings.$($property.Key))'. Expected value: '$($property.Value)'."
                    }
                } else {
                    Write-AlpacaWarning -Message "Settings file '$($settingsFile)': Property '$($property.Key)' is missing. Expected value: '$($property.Value)'."
                }
            }
        } catch {
             Write-AlpacaWarning -Message "Settings file '$($settingsFile)': Could not parse settings content. $($_.Exception.Message)"
        }
    }
}

# Check 3: No two AL-Go project directories may share a hyphen-prefix relationship
$treeOutput = gh api "repos/$Repo/git/trees/$([Uri]::EscapeDataString($Ref))?recursive=1" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-AlpacaWarning -Message "Could not fetch repository tree to check for hyphen-prefix project directory conflicts: $treeOutput"
} else {
    $conflictingPairs = @()

    try {
        $treeResponse = $treeOutput | ConvertFrom-Json -ErrorAction Stop

        if ($treeResponse.truncated) {
            Write-AlpacaWarning -Message "Repository tree was truncated. The hyphen-prefix project directory conflict check may be incomplete."
        }

        # Collect all AL-Go project directories that have a settings.json
        $projectDirs = @(
            $treeResponse.tree |
                Where-Object { $_.path -match '/\.AL-Go/settings\.json$' } |
                ForEach-Object {
                    $_.path -replace '/\.AL-Go/settings\.json$', ''
                }
        )

        # Detect pairs where one dir name is a hyphen-prefix of the other
        for ($i = 0; $i -lt $projectDirs.Count; $i++) {
            for ($j = $i + 1; $j -lt $projectDirs.Count; $j++) {
                $a = $projectDirs[$i]
                $b = $projectDirs[$j]
                if ($a.StartsWith("$($b)-") -or $b.StartsWith("$($a)-")) {
                    $conflictingPairs += "'$a' and '$b'"
                }
            }
        }
    } catch {
        Write-AlpacaWarning -Message "Could not parse repository tree to check for hyphen-prefix project directory conflicts: $($_.Exception.Message)"
    }

    if ($conflictingPairs.Count -gt 0) {
        $pairList = $conflictingPairs -join "`n  - "
        Write-AlpacaError "The following AL-Go project directories have hyphen-prefix naming conflicts which can cause unexpected AL-Go behavior:`n  - $pairList`n`nDirectories whose names differ only by a hyphen-separated suffix must not coexist.`nConsider renaming the directories to use underscores or other non-hyphen separators."
        throw "Hyphen-prefix project directory conflicts detected."

    }
}

exit 0