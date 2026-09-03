# Update README

Update the repository README with generated COSMO Alpaca sections and create either a pull request or a direct commit.

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | pwsh |
| actor | | The GitHub actor running the action | github.actor |
| token | Yes | Repository write token used for clone, commit, and pull request operations | |
| repo | | The target repository to update | github.repository |
| branch | | The target branch to update | github.ref_name |
| directCommit | | True if the action should create a direct commit against the branch; false to create a pull request | false |

## Behavior

The action will:

1. Collect AL-Go project data from the repository.
2. Create or update the auto-generated README section between markers.
3. Commit changes by creating a pull request (default) or a direct commit (when `directCommit` is true).

If no README changes are detected, no commit is created.

When a commit is created, the action uses `[skip ci]` only for direct commits (`directCommit: true`). Pull-request commits use the base commit message without `[skip ci]`.

## Prerequisites

Provide a token with repository write permissions via the `token` input.

When called from template workflows, this should typically be passed as `steps.ReadSecrets.outputs.TokenForPush`, allowing `useGhTokenWorkflow` to control whether `GhTokenWorkflow` or `GITHUB_TOKEN` is used.

## Example

```yaml
- name: Update README
  uses: ./Actions/Actions/UpdateReadme
  with:
    shell: pwsh
    token: ${{ steps.ReadSecrets.outputs.TokenForPush }}
    directCommit: ${{ github.event.inputs.directCommit }}
```

## OUTPUT

none
