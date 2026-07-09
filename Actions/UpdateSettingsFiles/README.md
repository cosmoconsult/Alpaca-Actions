# Update Settings Files

Updates the AL-Go settings files in the repository to enforce organization-level settings (e.g. organization build modes conditional settings).

When `dryRun` is enabled, the action only checks if settings are in sync and fails with an error if updates are needed.

## INPUT

### ENV variables

| Name | Required | Description |
| :-- | :-: | :-- |
| ALGoOrgSettings | | Organization-level AL-Go settings (from GitHub variable) |
| ALGoRepoSettings | | Repository-level AL-Go settings (from GitHub variable) |
| Settings | Yes | Merged AL-Go settings (populated by ReadSettings action) |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | pwsh |
| actor | | The GitHub actor running the action | github.actor |
| token | | Base64 encoded GhTokenWorkflow secret (not required for dryRun) | |
| repo | | The target repository to update | github.repository |
| branch | | The target branch to update | github.ref_name |
| directCommit | | True to create a direct commit, false to create a Pull Request | false |
| dryRun | | Only check if settings are in sync without making changes | false |

## OUTPUT

none
