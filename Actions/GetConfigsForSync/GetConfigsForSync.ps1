param (
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $true)]
    [string] $Token,
    [Parameter(HelpMessage = "Mode for the action: 'GetAndUpdate' searches AL-Go settings files and backend, 'Update' only queries backend", Mandatory = $false)]
    [ValidateSet("GetAndUpdate", "Update")]
    [string] $Mode = "GetAndUpdate",
    [Parameter(HelpMessage = "Comma-separated list of additional secret names to always include", Mandatory = $false)]
    [string] $AdditionalSecrets = "",
    [Parameter(HelpMessage = "All GitHub variables as JSON string", Mandatory = $false)]
    [string] $AllVariables = "{}",
    [Parameter(HelpMessage = "Comma-separated list of variable names to include", Mandatory = $false)]
    [string] $AdditionalVariables = ""
)

# Extract AL-Go settings from AllVariables
$OrgSettingsVariableValue = ""
$RepoSettingsVariableValue = ""
$EnvironmentSettingsVariableValue = ""

try {
    $allVarsJson = $AllVariables | ConvertFrom-Json -ErrorAction Stop
    if ($allVarsJson.PSObject.Properties.Name -contains "ALGoOrgSettings") {
        $OrgSettingsVariableValue = $allVarsJson.ALGoOrgSettings
    }
    if ($allVarsJson.PSObject.Properties.Name -contains "ALGoRepoSettings") {
        $RepoSettingsVariableValue = $allVarsJson.ALGoRepoSettings
    }
    if ($allVarsJson.PSObject.Properties.Name -contains "ALGoEnvSettings") {
        $EnvironmentSettingsVariableValue = $allVarsJson.ALGoEnvSettings
    }
} catch {
    Write-AlpacaWarning "Failed to parse AllVariables JSON: $($_)"
}

# Fall back to environment variables if not found in AllVariables
if ([string]::IsNullOrWhiteSpace($OrgSettingsVariableValue)) {
    $OrgSettingsVariableValue = $ENV:ALGoOrgSettings
}
if ([string]::IsNullOrWhiteSpace($RepoSettingsVariableValue)) {
    $RepoSettingsVariableValue = $ENV:ALGoRepoSettings
}
if ([string]::IsNullOrWhiteSpace($EnvironmentSettingsVariableValue)) {
    $EnvironmentSettingsVariableValue = $ENV:ALGoEnvSettings
}

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

$secretNames = @()

# Step 1: Find all relevant secret names for sync (only for GetAndUpdate mode)
if ($Mode -eq "GetAndUpdate") {
    Write-AlpacaGroupStart -Message "Searching for secret names in AL-Go settings files"
    
    # Define search patterns for secret keys
    $secretKeyPatterns = @("AuthTokenSecret")
    
    # Add additional patterns from AdditionalSecrets parameter
    if (-not [string]::IsNullOrWhiteSpace($AdditionalSecrets)) {
        $additionalSecretsList = $AdditionalSecrets -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        foreach ($secretName in $additionalSecretsList) {
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
            
            $foundSecrets = Find-SecretSyncSecretsInObject -Object $jsonObject -Patterns $secretKeyPatterns
            if ($foundSecrets.Count -gt 0) {
                Write-AlpacaOutput "Found $($foundSecrets.Count) secret name(s) in '$jsonFilePath': $($foundSecrets -join ', ')"
                $secretNames += $foundSecrets
            }
            
        } catch {
            Write-AlpacaWarning "Failed to parse JSON file '$jsonFilePath': $($_.Exception.Message)"
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
                $foundSecrets = Find-SecretSyncSecretsInObject -Object $settings -Patterns $secretKeyPatterns
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

# Step 2: Call Alpaca API to get all secret names from backend
try {
    Write-AlpacaGroupStart -Message "Fetching secret names from Alpaca backend"
    
    $backendSecretSyncStatus = Get-AlpacaConfigSyncStatus -Token $Token
    if ($backendSecretSyncStatus -and $backendSecretSyncStatus.syncedSecretNames.Count -gt 0) {
        Write-AlpacaOutput "Found $($backendSecretSyncStatus.syncedSecretNames.Count) secret name(s) in Alpaca backend: $($backendSecretSyncStatus.syncedSecretNames -join ', ')"
        $secretNames += $backendSecretSyncStatus.syncedSecretNames
    }

    Write-AlpacaGroupEnd -Message "Found $($backendSecretSyncStatus.syncedSecretNames.Count) secrets in Alpaca backend"
} catch {
    Write-AlpacaWarning "Failed to fetch secrets from Alpaca backend: $($_)"
    Write-AlpacaGroupEnd
}

# Step 3: Add additional secrets from AdditionalSecrets parameter
if (-not [string]::IsNullOrWhiteSpace($AdditionalSecrets)) {
    $additionalSecretsList = $AdditionalSecrets -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($additionalSecretsList.Count -gt 0) {
        Write-AlpacaOutput "Adding $($additionalSecretsList.Count) additional secret name(s): $($additionalSecretsList -join ', ')"
        $secretNames += $additionalSecretsList
    }
}

# Step 4: Remove duplicates and create comma-separated list of distinct secret names
$secretNames = $secretNames | Select-Object -Unique | Sort-Object
$secretNamesList = $secretNames -join ","

Write-AlpacaNotice "Total unique secret names: $($secretNames.Count)"
if ($secretNames.Count -gt 0) {
    Write-AlpacaOutput "Secret names: $secretNamesList"
}

# Step 5: Process variables from AllVariables parameter
$variablesObject = @{}
if (-not [string]::IsNullOrWhiteSpace($AdditionalVariables)) {
    Write-AlpacaGroupStart -Message "Processing variables for sync"
    
    $additionalVariablesList = $AdditionalVariables -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    
    try {
        $allVarsJson = $AllVariables | ConvertFrom-Json -ErrorAction Stop
        
        foreach ($varName in $additionalVariablesList) {
            if ($allVarsJson.PSObject.Properties.Name -contains $varName) {
                $variablesObject[$varName] = $allVarsJson.$varName
            }
        }
        
        Write-AlpacaNotice "Total variables: $($variablesObject.Count)"
    } catch {
        Write-AlpacaWarning "Failed to parse variables JSON: $($_)"
    }
    
    Write-AlpacaGroupEnd -Message "Processed $($variablesObject.Count) variables"
}

$variablesJson = $variablesObject | ConvertTo-Json -Compress -Depth 10

# Set output for GitHub Actions
if ($env:GITHUB_OUTPUT) {
    "secretsForSync=$secretNamesList" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    Write-AlpacaOutput "Set output variable 'secretsForSync'"
    
    "Variables=$variablesJson" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    Write-AlpacaOutput "Set output variable 'Variables'"
}
