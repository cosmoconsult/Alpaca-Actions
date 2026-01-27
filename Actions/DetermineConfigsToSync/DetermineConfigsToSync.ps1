param (
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $true)]
    [string] $Token,
    [Parameter(HelpMessage = "Mode for the action: 'GetAndUpdate' searches AL-Go settings files and backend, 'Update' only queries backend", Mandatory = $false)]
    [ValidateSet("GetAndUpdate", "Update")]
    [string] $Mode = "GetAndUpdate",
    [Parameter(HelpMessage = "GitHub variables as JSON string (from toJson(vars))", Mandatory = $true)]
    [string] $GitHubVariablesJson = "",
    [Parameter(HelpMessage = "Comma-separated list of secret names to include", Mandatory = $false)]
    [string] $IncludeSecrets = "",
    [Parameter(HelpMessage = "Comma-separated list of variable names to include", Mandatory = $false)]
    [string] $IncludeVariables = ""
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

# Parse GitHub variables JSON once
$gitHubVariables = $null
try {
    $gitHubVariables = $GitHubVariablesJson | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-AlpacaWarning "Failed to parse GitHubVariablesJson: $($_)"
}

# Extract AL-Go settings from GitHub variables
$OrgSettingsVariableValue = ""
$RepoSettingsVariableValue = ""
$EnvironmentSettingsVariableValue = ""

if ($gitHubVariables) {
    if ($gitHubVariables.PSObject.Properties["ALGoOrgSettings"]) {
        $OrgSettingsVariableValue = $gitHubVariables.ALGoOrgSettings
    }
    if ($gitHubVariables.PSObject.Properties["ALGoRepoSettings"]) {
        $RepoSettingsVariableValue = $gitHubVariables.ALGoRepoSettings
    }
    if ($gitHubVariables.PSObject.Properties["ALGoEnvSettings"]) {
        $EnvironmentSettingsVariableValue = $gitHubVariables.ALGoEnvSettings
    }
}

# Fall back to environment variables if not found in GitHub variables
if ([string]::IsNullOrWhiteSpace($OrgSettingsVariableValue)) {
    $OrgSettingsVariableValue = $ENV:ALGoOrgSettings
}
if ([string]::IsNullOrWhiteSpace($RepoSettingsVariableValue)) {
    $RepoSettingsVariableValue = $ENV:ALGoRepoSettings
}
if ([string]::IsNullOrWhiteSpace($EnvironmentSettingsVariableValue)) {
    $EnvironmentSettingsVariableValue = $ENV:ALGoEnvSettings
}

$secretNames = @()
$variableNames = @()

# Step 1: Find all relevant secret names for sync (only for GetAndUpdate mode)
if ($Mode -eq "GetAndUpdate") {
    Write-AlpacaGroupStart -Message "Searching for secret names in AL-Go settings files"
    
    # Define search patterns for secret keys
    $secretKeyPatterns = @("AuthTokenSecret")
    
    # Add additional patterns from IncludeSecrets parameter
    if (-not [string]::IsNullOrWhiteSpace($IncludeSecrets)) {
        $includeSecretsList = $IncludeSecrets -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        foreach ($secretName in $includeSecretsList) {
            $pattern = "${secretName}SecretName"
            $secretKeyPatterns += $pattern
            Write-AlpacaOutput "Added search pattern: $pattern"
        }
    }
    
    # Find all AL-Go settings files
    $jsonFilePaths = Find-ALGoSettingsFiles -WorkspacePath $env:GITHUB_WORKSPACE
    
    # Parse JSON files and extract secret names
    Write-AlpacaOutput "Searching $($jsonFilePaths.Count) AL-Go settings JSON files in repository"
    
    foreach ($jsonFilePath in $jsonFilePaths) {
        if (-not (Test-Path $jsonFilePath)) {
            continue
        }

        Write-AlpacaOutput "Searching file: $jsonFilePath"
        try {
            $content = Get-Content -Path $jsonFilePath -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrWhiteSpace($content)) {
                continue
            }
            
            $jsonObject = $content | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($null -eq $jsonObject) {
                continue
            }
            
            $foundSecrets = Find-SecretsToSyncInObject -Object $jsonObject -Patterns $secretKeyPatterns
            if ($foundSecrets.Count -gt 0) {
                Write-AlpacaOutput "Found $($foundSecrets.Count) secret name(s) in '$jsonFilePath': $($foundSecrets -join ', ')"
                $secretNames += $foundSecrets
            }
            
        } catch {
            Write-AlpacaWarning "Failed to parse JSON file '$jsonFilePath':`n$_"
        }
        
    }
    
    # Parse JSON from AL-Go settings parameters
    Write-AlpacaOutput "Searching AL-Go settings variables"
    
    $settingsVariables = @(
        @{ Name = "organization"; Value = $OrgSettingsVariableValue},
        @{ Name = "repository"; Value = $RepoSettingsVariableValue},
        @{ Name = "environment"; Value = $EnvironmentSettingsVariableValue}
    )
    
    foreach ($settingsVar in $settingsVariables) {
        if ([string]::IsNullOrWhiteSpace($settingsVar.Value)) {
            continue
        }

        Write-AlpacaOutput "Searching $($settingsVar.Name) settings variable"
        try {
            $settings = $settingsVar.Value | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $settings) {
                $foundSecrets = Find-SecretsToSyncInObject -Object $settings -Patterns $secretKeyPatterns
                if ($foundSecrets.Count -gt 0) {
                    Write-AlpacaOutput "Found $($foundSecrets.Count) secret name(s) in $($settingsVar.Name) settings: $($foundSecrets -join ', ')"
                    $secretNames += $foundSecrets
                }
            }
        } catch {
            Write-AlpacaWarning "Failed to parse $($settingsVar.Name) settings: $($_)"
        }
    }
    
    Write-AlpacaGroupEnd -Message "Found $($secretNames.Count) secret names in AL-Go settings"
}
else {
    Write-AlpacaOutput "Skipping AL-Go settings search (Mode: $Mode)"
}

# Step 2: Call Alpaca API to get config names from backend
try {
    Write-AlpacaGroupStart -Message "Fetching config names from Alpaca backend"
    
    $backendConfigSyncStatus = Get-AlpacaConfigSyncStatus -Token $Token
    
    # Add synced secret names from backend
    if ($backendConfigSyncStatus -and $backendConfigSyncStatus.syncedSecretNames.Count -gt 0) {
        Write-AlpacaOutput "Found $($backendConfigSyncStatus.syncedSecretNames.Count) secret name(s) in Alpaca backend: $($backendConfigSyncStatus.syncedSecretNames -join ', ')"
        $secretNames += $backendConfigSyncStatus.syncedSecretNames
    }
    
    # Add synced variable names from backend
    if ($backendConfigSyncStatus -and $backendConfigSyncStatus.syncedVariableNames.Count -gt 0) {
        Write-AlpacaOutput "Found $($backendConfigSyncStatus.syncedVariableNames.Count) variable name(s) in Alpaca backend: $($backendConfigSyncStatus.syncedVariableNames -join ', ')"
        $variableNames += $backendConfigSyncStatus.syncedVariableNames
    }

    Write-AlpacaGroupEnd -Message "Found $($backendConfigSyncStatus.syncedSecretNames.Count) secrets and $($backendConfigSyncStatus.syncedVariableNames.Count) variables in Alpaca backend"
} catch {
    Write-AlpacaWarning "Failed to fetch configs from Alpaca backend: $($_)"
    Write-AlpacaGroupEnd
}

# Step 3: Add secrets and variables from Include parameters
if (-not [string]::IsNullOrWhiteSpace($IncludeSecrets)) {
    $includeSecretsList = $IncludeSecrets -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($includeSecretsList.Count -gt 0) {
        Write-AlpacaOutput "Adding $($includeSecretsList.Count) secret name(s) from IncludeSecrets: $($includeSecretsList -join ', ')"
        $secretNames += $includeSecretsList
    }
}

if (-not [string]::IsNullOrWhiteSpace($IncludeVariables)) {
    $includeVariablesList = $IncludeVariables -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($includeVariablesList.Count -gt 0) {
        Write-AlpacaOutput "Adding $($includeVariablesList.Count) variable name(s) from IncludeVariables: $($includeVariablesList -join ', ')"
        $variableNames += $includeVariablesList
    }
}

# Step 4: Remove duplicates and create comma-separated list of distinct secret names
$secretNames = $secretNames | Select-Object -Unique -CaseInsensitive | Sort-Object
$secretNamesList = $secretNames -join ","

Write-AlpacaNotice "Total unique secret names: $($secretNames.Count)"
if ($secretNames.Count -gt 0) {
    Write-AlpacaOutput "Secret names: $secretNamesList"
}

# Step 5: Remove duplicates and process variables
$variableNames = $variableNames | Select-Object -Unique -CaseInsensitive | Sort-Object

$variablesObject = @{}
if ($gitHubVariables -and $variableNames.Count -gt 0) {
    Write-AlpacaGroupStart -Message "Processing variables for sync"
    
    foreach ($varName in $variableNames) {
        if ($gitHubVariables.PSObject.Properties[$varName]) {
            $variablesObject[$varName] = $gitHubVariables.$varName
            Write-AlpacaOutput "Added variable: $varName"
        } else {
            Write-AlpacaOutput "Variable not found in GitHub variables, skipping: $varName"
        }
    }
    
    Write-AlpacaNotice "Total variables: $($variablesObject.Count)"
    Write-AlpacaGroupEnd -Message "Processed $($variablesObject.Count) variables"
}

$variablesJson = $variablesObject | ConvertTo-Json -Compress -Depth 10

# Set output for GitHub Actions
if ($env:GITHUB_OUTPUT) {
    "secretNames=$secretNamesList" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    Write-AlpacaOutput "Set output variable 'secretNames'"
    
    "variablesJson=$variablesJson" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    Write-AlpacaOutput "Set output variable 'variablesJson'"
}
