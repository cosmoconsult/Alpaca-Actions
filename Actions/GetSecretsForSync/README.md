# Get Secrets For Sync

Find all secret names from AL-Go settings files and Alpaca backend to prepare for synchronization. This action can run in two modes to either scan AL-Go settings files and query the backend, or only query the backend.

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
| orgSettingsVariableValue | | AL-Go organization settings as JSON string | env.ALGoOrgSettings |
| repoSettingsVariableValue | | AL-Go repository settings as JSON string | env.ALGoRepoSettings |
| environmentSettingsVariableValue | | AL-Go environment settings as JSON string | env.ALGoEnvSettings |
| additionalSecrets | | Comma-separated list of additional secret names to always include | (empty) |

## Behavior

### Mode: GetAndUpdate
1. Searches for the following specific JSON files:
   - `.github/AL-Go-Settings.json`
   - `.AL-Go/*.settings.json` (all files matching this pattern in root and subdirectories)
   - `.github/*.settings.json` (all files matching this pattern)
2. Parses JSON from parameters:
   - `orgSettingsVariableValue` (defaults to `ALGoOrgSettings` environment variable)
   - `repoSettingsVariableValue` (defaults to `ALGoRepoSettings` environment variable)
   - `environmentSettingsVariableValue` (defaults to `ALGoEnvSettings` environment variable)
3. Looks for keys ending with `*SecretName` or `*Secret`
4. Extracts the values of these keys as potential secret names
5. Calls the Alpaca API to retrieve all secret names currently stored in the backend (in a k8s secret)
6. Combines secret names from AL-Go settings with backend secrets
7. Adds any additional secret names from the `additionalSecrets` parameter (if provided)
8. Removes duplicates and outputs a comma-separated list

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

## Usage Example

```yaml
# Example 1: GetAndUpdate mode (default) - scans AL-Go settings and backend
- name: Get Secrets For Sync
  uses: ./Actions/GetSecretsForSync
  id: getSecrets
  with:
    token: ${{ github.token }}
    mode: GetAndUpdate

- name: Use Secret Names
  run: |
    echo "Secret names: ${{ steps.getSecrets.outputs.secretsForSync }}"

# Example 2: Update mode - only queries backend
- name: Get Secrets For Sync
  uses: ./Actions/GetSecretsForSync
  id: getSecrets
  with:
    token: ${{ github.token }}
    mode: Update

# Example 3: With additional secrets added
- name: Get Secrets For Sync
  uses: ./Actions/GetSecretsForSync
  id: getSecrets
  with:
    token: ${{ github.token }}
    mode: GetAndUpdate
    additionalSecrets: 'AuthContext,LicenseFileSecret,MyCustomSecret'
```
