# Update Alpaca System Files

Update COSMO Alpaca system files (inspired by [AL-Go Action - Check for updates](https://github.com/microsoft/AL-Go-Actions/tree/main/CheckForUpdates))

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| actor | | The GitHub actor running the action | github.actor |
| token | | Base64 encoded GhTokenWorkflow secret | |
| templateUrl | | URL of the template repository (default is the template repository used to create the repository) | default |
| downloadLatest | Yes | Set this input to true in order to download latest version of the template repository (else it will reuse the SHA from last update) | |
| updateBranch | | Set the branch to update. In case `directCommit` parameter is set to true, then the branch the action is run on will be updated | github.ref_name |
| directCommit | | True if the action should create a direct commit against the branch or false to create a Pull Request | false |

## OUTPUT

none
