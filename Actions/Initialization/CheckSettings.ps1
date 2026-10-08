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
    Write-AlpacaError "The configuration file '$($deprecatedConfigFile)' is deprecated.`n`nPlease migrate to AL-Go settings.`nSee: https://docs.cosmoconsult.com/en-us/cloud-service/alpaca/github/setup-al-go-settings.html#migrating-from-alpacajson"
    throw "The configuration file '$($deprecatedConfigFile)' is deprecated."
}
elseif ($output -notmatch '404|Not Found') {
    Write-AlpacaWarning -Message "Could not check '$($deprecatedConfigFile)': $output"
}

# Check 2: Expected workflow settings (only for relevant workflows)
$expectedWorkflowSettings = @{
    'Test Current'    = @{
        artifact           = '////latest'
        versioningStrategy = 15
    }
    'Test Next Minor' = @{
        artifact           = '////nextminor'
        versioningStrategy = 15
    }
    'Test Next Major' = @{
        artifact           = '////nextmajor'
        versioningStrategy = 15
    }
}.GetEnumerator() | Where-Object { $_.Key -eq $Workflow } | Select-Object -First 1 -ExpandProperty Value

if ($expectedWorkflowSettings) {
    $settingsFile = ".github/$($Workflow).settings.json"
    $output = gh api (Get-GitHubApiFileContentUrl -Repo $Repo -FilePath $settingsFile -Ref $Ref) 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($output -match '404|Not Found') {
            Write-AlpacaWarning -Message "Settings file '$($settingsFile)' is missing."
        }
        else {
            Write-AlpacaWarning -Message "Could not check '$($settingsFile)': $output"
        }
    }
    else {
        try {
            $rawContent = ($output | ConvertFrom-Json).content -replace '\s', ''
            $settings = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($rawContent)) | ConvertFrom-Json

            foreach ($property in $expectedWorkflowSettings.GetEnumerator()) {
                if ($settings | Get-Member -Name $property.Key -MemberType NoteProperty) {
                    if ($settings.$($property.Key) -ne $property.Value) {
                        Write-AlpacaWarning -Message "Settings file '$($settingsFile)': Property '$($property.Key)' has unexpected value '$($settings.$($property.Key))'. Expected value: '$($property.Value)'."
                    }
                }
                else {
                    Write-AlpacaWarning -Message "Settings file '$($settingsFile)': Property '$($property.Key)' is missing. Expected value: '$($property.Value)'."
                }
            }
        }
        catch {
            Write-AlpacaWarning -Message "Settings file '$($settingsFile)': Could not parse settings content. $($_.Exception.Message)"
        }
    }
}

# Check 3: Ensure shell settings in AL-Go-Settings.json do not use powershell 5
$alGoSettingsFile = '.github/AL-Go-Settings.json'
$output = gh api (Get-GitHubApiFileContentUrl -Repo $Repo -FilePath $alGoSettingsFile -Ref $Ref) 2>&1
if ($LASTEXITCODE -eq 0) {
    try {
        $rawContent = ($output | ConvertFrom-Json).content -replace '\s', ''
        $settings = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($rawContent)) | ConvertFrom-Json

        $invalidSettings = @()
        if (($settings | Get-Member -Name 'shell' -MemberType NoteProperty) -and $settings.shell -ieq 'powershell') {
            $invalidSettings += 'shell'
        }
        if (($settings | Get-Member -Name 'githubRunnerShell' -MemberType NoteProperty) -and $settings.githubRunnerShell -ieq 'powershell') {
            $invalidSettings += 'githubRunnerShell'
        }
    }
    catch {
        Write-AlpacaWarning -Message "Settings file '$($alGoSettingsFile)': Could not parse settings content. $($_.Exception.Message)"
    }

    if ($invalidSettings.Count -gt 0) {
        $propertyList = $invalidSettings -join ', '
        Write-AlpacaError -Message "Settings file '$($alGoSettingsFile)' must not set '$propertyList' to 'powershell'. PowerShell 5 is not supported by COSMO Alpaca. Use 'pwsh' instead." -GitHubAnnotationParams "file=$alGoSettingsFile"
        throw "Invalid shell settings in AL-Go-Settings.json"
    }

}
elseif ($output -notmatch '404|Not Found') {
    Write-AlpacaWarning -Message "Could not check '$($alGoSettingsFile)': $output"
}

exit 0
