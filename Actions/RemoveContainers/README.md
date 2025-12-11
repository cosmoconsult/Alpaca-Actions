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
| filterJson | | Optional Alpaca container information to filter containers by in JSON format | |

## OUTPUT

### ENV variables

none

### OUTPUT variables

none
