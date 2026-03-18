# Determine Configs To Sync

Finds all secret names from AL-Go settings files and Alpaca backend, and gets the specified variables to prepare for synchronization. This action can run in two modes to either scan AL-Go settings files and query the backend, or only query the backend.

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| ALPACA_BACKEND_URL | COSMO Alpaca Backend URL |
| ALGoOrgSettings | (Optional) JSON string containing AL-Go organization settings - can be passed as parameter instead |
| ALGoRepoSettings | (Optional) JSON string containing AL-Go repository settings - can be passed as parameter instead |
| ALGoEnvSettings | (Optional) JSON string containing AL-Go environment settings - can be passed as parameter instead |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| token | | The GitHub token running the action | github.token |
| mode | | Mode for the action: 'GetAndUpdate' or 'Update' - determines if AL-Go settings should be scanned | GetAndUpdate |
| gitHubVariablesJson | true | GitHub variables as JSON string (from toJson(vars)) | |
| includeSecrets | | Comma-separated list of secret names to include | (empty) |
| includeVariables | | Comma-separated list of variable names to include | (empty) |

## Behavior

### Mode: GetAndUpdate
1. Searches for the following specific AL-Go settings JSON files:
   - `.github/AL-Go-Settings.json`
   - `.AL-Go/settings.json` (all files matching this pattern in root and subdirectories)
   - `.AL-Go/*.settings.json` (all files matching this pattern in root and subdirectories)
   - `.github/*.settings.json` (all files matching this pattern)
1. Extracts AL-Go settings from `gitHubVariablesJson` parameter:
   - `ALGoOrgSettings` (falls back to environment variable if not found)
   - `ALGoRepoSettings` (falls back to environment variable if not found)
   - `ALGoEnvSettings` (falls back to environment variable if not found)
1. Scans all AL-Go settings JSON keys and string values for potential secret names:
   - Looks for keys matching configured secret key patterns (for example, `AuthTokenSecret` or `${IncludeSecrets}SecretName`) and extracts their values as potential secret names
   - Additionally, searches all string values for GitHub Actions expression patterns like `${{SECRETNAME}}` and extracts `SECRETNAME` as a potential secret name
1. Calls the Alpaca API to retrieve all config names currently stored in the backend:
   - Retrieves secret names from `syncedSecretNames`
   - Retrieves variable names from `syncedVariableNames`
1. Combines secret names from AL-Go settings with backend secrets
1. Adds any secret names from the `includeSecrets` parameter (if provided)
1. Adds any variable names from the `includeVariables` parameter (if provided)
1. Removes duplicates and processes variables by looking up each variable name in `gitHubVariablesJson`
1. Removes duplicates and outputs a comma-separated list of secret names and a JSON object of variables

### Mode: Update
1. Calls the Alpaca API to retrieve all config names currently stored in the backend:
   - Retrieves secret names from `syncedSecretNames`
   - Retrieves variable names from `syncedVariableNames`
1. Adds any secret names from the `includeSecrets` parameter (if provided)
1. Adds any variable names from the `includeVariables` parameter (if provided)
1. Removes duplicates and processes variables by looking up each variable name in `gitHubVariablesJson`
1. Removes duplicates and outputs a comma-separated list of secret names and a JSON object of variables

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| secretNames | Comma-separated list of distinct secret names found in AL-Go settings, Alpaca backend and IncludeSecrets |
| variablesJson | JSON object with variable values found in workflow variables for variable names defined in Alpaca backend and IncludeVariables |

## Usage Example

```yaml
# Example 1: GetAndUpdate mode (default) - scans AL-Go settings and backend
- name: Determine Configs To Sync
  uses: cosmoconsult/Alpaca-Actions/Actions/DetermineConfigsToSync@main
  id: getConfigs
  with:
    token: ${{ github.token }}
    mode: GetAndUpdate
    gitHubVariablesJson: ${{ toJson(vars) }}

- name: Use Secret Names
  run: |
    echo "Secret names: ${{ steps.getConfigs.outputs.secretNames }}"

- name: Use Variables Json
  run: |
    echo "Variables: ${{ steps.getConfigs.outputs.variablesJson }}"

# Example 2: Update mode - only queries backend
- name: Determine Configs To Sync
  uses: cosmoconsult/Alpaca-Actions/Actions/DetermineConfigsToSync@main
  id: getConfigs
  with:
    token: ${{ github.token }}
    mode: Update
    gitHubVariablesJson: ${{ toJson(vars) }}

# Example 3: With additional secrets and variables
- name: Determine Configs To Sync
  uses: cosmoconsult/Alpaca-Actions/Actions/DetermineConfigsToSync@main
  id: getConfigs
  with:
    token: ${{ github.token }}
    mode: GetAndUpdate
    gitHubVariablesJson: ${{ toJson(vars) }}
    includeSecrets: 'AuthContext,LicenseFileSecret,MyCustomSecret'
    includeVariables: 'ALGoOrgSettings,ALGoRepoSettings,CustomVariable'
```
