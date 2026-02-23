Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

# Check 1: Deprecated config file
$deprecatedConfigFile = '.alpaca/alpaca.json'
$output = gh api "repos/$($env:GITHUB_REPOSITORY)/contents/$($deprecatedConfigFile)?ref=$($env:GITHUB_SHA)" --silent 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-AlpacaWarning -Message "The configuration file '$($deprecatedConfigFile)' is deprecated.`nThis will become an error in the future.`n`nPlease migrate to AL-Go settings.`nSee: https://docs.cosmoconsult.com/en-us/cloud-service/devops-docker-selfservice/containers/setup-cosmo-json.html"
} elseif ($output -notmatch '404|Not Found') {
    Write-AlpacaWarning -Message "Could not check '$($deprecatedConfigFile)': $output"
}

# Check 2: Expected workflow settings (only for relevant workflows)
$currentWorkflow = $env:GITHUB_WORKFLOW
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
}.GetEnumerator() | Where-Object { $_.Key -eq $currentWorkflow } | Select-Object -First 1 -ExpandProperty Value

if ($expectedWorkflowSettings) {
    $settingsFile = ".github/$($currentWorkflow).settings.json"
    # $encodedWorkflowName = $currentWorkflow -replace ' ', '%20'
    # $encodedSettingsFile = ".github/$($encodedWorkflowName).Settings.json"

    # $output = gh api "repos/$($env:GITHUB_REPOSITORY)/contents/$($encodedSettingsFile)?ref=$($env:GITHUB_SHA)" --silent 2>&1
    $output = gh api "repos/$($env:GITHUB_REPOSITORY)/contents/$($settingsFile)?ref=$($env:GITHUB_SHA)" --silent 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($output -match '404|Not Found') {
            Write-AlpacaWarning -Message "Settings file '$($settingsFile)' is missing."
        } else {
            Write-AlpacaWarning -Message "Could not check '$($settingsFile)': $output"
        }
    } else {
        $rawContent = ($output | ConvertFrom-Json).content -replace '\s', ''
        $settings = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($rawContent)) | ConvertFrom-Json
        Write-AlpacaOutput -Message "Settings file '$($settingsFile)' content:`n$([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($rawContent)))"

        $issues = [System.Collections.Generic.List[string]]::new()
        foreach ($property in $expectedWorkflowSettings.GetEnumerator()) {
            if ($settings | Get-Member -Name $property.Key -MemberType NoteProperty) {
                if ($settings.$($property.Key) -ne $property.Value) {
                    $issues.Add("Property '$($property.Key)' has unexpected value '$($settings.$($property.Key))'. Expected value: '$($property.Value)'.")
                }
            } else {
                $issues.Add("Property '$($property.Key)' is missing. Expected value: '$($property.Value)'.")
            }
        }

        if ($issues.Count -gt 0) {
            Write-AlpacaWarning -Message "Settings file '$($settingsFile)' has issues:`n$($issues -join "`n")"
        }
    }
}

exit 0
