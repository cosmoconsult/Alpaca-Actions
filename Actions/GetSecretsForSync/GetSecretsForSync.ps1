param (
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $true)]
    [string] $Token,
    [Parameter(HelpMessage = "Mode for the action: 'GetAndUpdate' searches AL-Go settings files and backend, 'Update' only queries backend", Mandatory = $false)]
    [ValidateSet("GetAndUpdate", "Update")]
    [string] $Mode = "GetAndUpdate",
    [Parameter(HelpMessage = "AL-Go organization settings as JSON string", Mandatory = $false)]
    [string] $OrgSettingsVariableValue = "",
    [Parameter(HelpMessage = "AL-Go repository settings as JSON string", Mandatory = $false)]
    [string] $RepoSettingsVariableValue = "",
    [Parameter(HelpMessage = "AL-Go environment settings as JSON string", Mandatory = $false)]
    [string] $EnvironmentSettingsVariableValue = "",
    [Parameter(HelpMessage = "Comma-separated list of additional secret names to always include", Mandatory = $false)]
    [string] $AdditionalSecrets = ""
)

# Fall back to environment variables if parameters are empty
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

# Recursively search for keys matching the patterns
function Get-SecretNamesFromObject {
    param (
        [Parameter(Mandatory = $true)]
        $Object,
        [string[]] $Patterns
    )
    
    $names = @()
    
    if ($Object -is [PSCustomObject]) {
        $properties = $Object | Get-Member -MemberType NoteProperty
        foreach ($prop in $properties) {
            $propName = $prop.Name
            $propValue = $Object.$propName
            
            # Check if property name matches any pattern
            $matchesPattern = $false
            foreach ($pattern in $Patterns) {
                if ($propName -like $pattern) {
                    $matchesPattern = $true
                    break
                }
            }
            
            if ($matchesPattern -and (-not [string]::IsNullOrWhiteSpace($propValue))) {
                # If the value is a string, add it to the list
                if ($propValue -is [string]) {
                    $names += $propValue
                }
            }
            
            # Also check if property value contains ${{SECRETNAME}} pattern
            if ($propValue -is [string] -and $propValue -match '\$\{\{([^}]+)\}\}') {
                # Extract secret name from ${{SECRETNAME}} pattern
                $secretName = $Matches[1].Trim()
                if (-not [string]::IsNullOrWhiteSpace($secretName)) {
                    $names += $secretName
                }
            }
            
            # Recursively search nested objects
            $names += Get-SecretNamesFromObject -Object $propValue -Patterns $Patterns
        }
    }
    elseif ($Object -is [array]) {
        foreach ($item in $Object) {
            $names += Get-SecretNamesFromObject -Object $item -Patterns $Patterns
        }
    }
    
    return $names
}


$secretNames = @()

# Step 1: Find all relevant secret names for sync (only for GetAndUpdate mode)
if ($Mode -eq "GetAndUpdate") {
    Write-AlpacaGroupStart -Message "Searching for secret names in AL-Go settings files"
    
    # Define search patterns for secret keys
    $secretKeyPatterns = @("*SecretName", "*Secret")
    
    # Find all AL-Go settings files
    $jsonFilePaths = Find-ALGoSettingsFiles -WorkspacePath $env:GITHUB_WORKSPACE
    
    # Parse JSON files and extract secret names
    Write-AlpacaOutput "Searching $($jsonFilePaths.Count) AL-Go settings JSON files in repository"
    
    foreach ($jsonFilePath in $jsonFilePaths) {
        if (Test-Path $jsonFilePath) {
            continue;
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
            
            $foundSecrets = Get-SecretNamesFromObject -Object $jsonObject -Patterns $secretKeyPatterns
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
    
    if (-not [string]::IsNullOrWhiteSpace($OrgSettingsVariableValue)) {
        Write-AlpacaOutput "Searching organization settings variable"
        try {
            $orgSettings = $OrgSettingsVariableValue | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $orgSettings) {
                $foundSecrets = Get-SecretNamesFromObject -Object $orgSettings -Patterns $secretKeyPatterns
                if ($foundSecrets.Count -gt 0) {
                    Write-AlpacaOutput "Found $($foundSecrets.Count) secret name(s) in organization settings: $($foundSecrets -join ', ')"
                    $secretNames += $foundSecrets
                }
            }
        } catch {
            Write-AlpacaError "Failed to parse organization settings: $($_.Exception.Message)"
            throw "Cannot proceed with invalid organization settings"
        }
    }
    
    if (-not [string]::IsNullOrWhiteSpace($RepoSettingsVariableValue)) {
        Write-AlpacaOutput "Searching repository settings variable"
        try {
            $repoSettings = $RepoSettingsVariableValue | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $repoSettings) {
                $foundSecrets = Get-SecretNamesFromObject -Object $repoSettings -Patterns $secretKeyPatterns
                if ($foundSecrets.Count -gt 0) {
                    Write-AlpacaOutput "Found $($foundSecrets.Count) secret name(s) in repository settings: $($foundSecrets -join ', ')"
                    $secretNames += $foundSecrets
                }
            }
        } catch {
            Write-AlpacaError "Failed to parse repository settings: $($_.Exception.Message)"
            throw "Cannot proceed with invalid repository settings"
        }
    }
    
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentSettingsVariableValue)) {
        Write-AlpacaOutput "Searching environment settings variable"
        try {
            $envSettings = $EnvironmentSettingsVariableValue | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $envSettings) {
                $foundSecrets = Get-SecretNamesFromObject -Object $envSettings -Patterns $secretKeyPatterns
                if ($foundSecrets.Count -gt 0) {
                    Write-AlpacaOutput "Found $($foundSecrets.Count) secret name(s) in environment settings: $($foundSecrets -join ', ')"
                    $secretNames += $foundSecrets
                }
            }
        } catch {
            Write-AlpacaError "Failed to parse environment settings: $($_.Exception.Message)"
            throw "Cannot proceed with invalid environment settings"
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
    
    $backendSecretSyncStatus = Get-AlpacaSecretSyncStatus -Token $Token
    if ($backendSecretSyncStatus -and $backendSecretSyncStatus.syncedSecretNames.Count -gt 0) {
        Write-AlpacaOutput "Found $($backendSecretSyncStatus.syncedSecretNames.Count) secret name(s) in Alpaca backend: $($backendSecretSyncStatus.syncedSecretNames -join ', ')"
        $secretNames += $backendSecretSyncStatus.syncedSecretNames
    }

    Write-AlpacaGroupEnd -Message "Found $($backendSecretSyncStatus.syncedSecretNames.Count) secrets in Alpaca backend"
} catch {
    Write-AlpacaError "Failed to fetch secrets from Alpaca backend: $($_.Exception.Message)"
    Write-AlpacaGroupEnd
    # Throw to prevent potential secret deletion due to incomplete data
    throw "Cannot proceed without backend secret information"
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

# Set output for GitHub Actions
if ($env:GITHUB_OUTPUT) {
    "secretsForSync=$secretNamesList" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    Write-AlpacaOutput "Set output variable 'secretsForSync'"
}
