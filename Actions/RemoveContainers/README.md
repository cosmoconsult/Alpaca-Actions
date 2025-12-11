# Remove Containers

Remove COSMO Alpaca containers

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| ALPACA_BACKEND_URL | COSMO Alpaca Backend URL |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| token | | The GitHub token running the action | github.token |
| containersJson | Yes | An array of Alpaca container informations in compressed JSON format | |
| project | | Optional project name to filter containers to remove | |
| buildMode | | Optional build mode to filter containers to remove | |

## OUTPUT

### ENV variables

none

### OUTPUT variables

none
