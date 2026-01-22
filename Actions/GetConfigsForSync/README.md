# Get Configs For Sync

Find all secret names from AL-Go settings files and Alpaca backend, and gets specified variables to prepare for synchronization. This action can run in two modes to either scan AL-Go settings files and query the backend, or only query the backend.

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
| additionalSecrets | | Comma-separated list of additional secret names to always include | (empty) |
| allVariables | | All GitHub variables as JSON string (from toJson(vars)) - should contain ALGoOrgSettings, ALGoRepoSettings, ALGoEnvSettings | {} |
| additionalVariables | | Comma-separated list of variable names to include | (empty) |

## Behavior

### Mode: GetAndUpdate
1. Searches for the following specific JSON files:
   - `.github/AL-Go-Settings.json`
   - `.AL-Go/settings.json` (all files matching this pattern in root and subdirectories)
   - `.AL-Go/*.settings.json` (all files matching this pattern in root and subdirectories)
   - `.github/*.settings.json` (all files matching this pattern)
2. Extracts AL-Go settings from `allVariables` parameter:
   - `ALGoOrgSettings` from allVariables (falls back to environment variable if not found)
   - `ALGoRepoSettings` from allVariables (falls back to environment variable if not found)
   - `ALGoEnvSettings` from allVariables (falls back to environment variable if not found)
3. Scans all JSON keys and string values for potential secret names:
   - Looks for keys ending with `*SecretName` or `*Secret` and extracts their values as potential secret names
   - Additionally, searches all string values for GitHub Actions expression patterns like `${{SECRETNAME}}` and extracts `SECRETNAME` as a potential secret name
5. Calls the Alpaca API to retrieve all secret names currently stored in the backend (in a k8s secret)
6. Combines secret names from AL-Go settings with backend secrets
7. Adds any additional secret names from the `additionalSecrets` parameter (if provided)
8. Processes variables from `additionalVariables` parameter, extracting their values from `allVariables`
9. Removes duplicates and outputs a comma-separated list of secret names and a JSON object of variables

### Mode: Update
- Only calls the Alpaca API to retrieve all secret names currently stored in the backend (in a k8s secret)
- Adds any additional secret names from the `additionalSecrets` parameter (if provided)
- Outputs a comma-separated list of backend secret names

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| secretsForSync | Comma-separated list of distinct secret names found in AL-Go settings and Alpaca backend |
| Variables | JSON object with unencoded variable values for the specified additionalVariables |

## Usage Example

```yaml
# Example 1: GetAndUpdate mode (default) - scans AL-Go settings and backend
- name: Get Configs For Sync
  uses: cosmoconsult/Alpaca-Actions/Actions/GetConfigsForSync@main
  id: getConfigs
  with:
    token: ${{ github.token }}
    mode: GetAndUpdate
    allVariables: ${{ toJson(vars) }}

- name: Use Secret Names
  run: |
    echo "Secret names: ${{ steps.getConfigs.outputs.secretsForSync }}"

# Example 2: Update mode - only queries backend
- name: Get Configs For Sync
  uses: cosmoconsult/Alpaca-Actions/Actions/GetConfigsForSync@main
  id: getConfigs
  with:
    token: ${{ github.token }}
    mode: Update
    allVariables: ${{ toJson(vars) }}

# Example 3: With additional secrets and variables
- name: Get Configs For Sync
  uses: cosmoconsult/Alpaca-Actions/Actions/GetConfigsForSync@main
  id: getConfigs
  with:
    token: ${{ github.token }}
    mode: GetAndUpdate
    additionalSecrets: 'AuthContext,LicenseFileSecret,MyCustomSecret'
    allVariables: ${{ toJson(vars) }}
    additionalVariables: 'ALGoOrgSettings,ALGoRepoSettings,CustomVariable'
```
