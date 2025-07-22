# Create Containers

Create a COSMO Alpaca container for each project

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
| projectsJson | Yes | An array of AL-Go projects in compressed JSON format | |

## OUTPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| ALPACA_CONTAINERS_JSON | An array of Alpaca container informations in compressed JSON format |

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| containersJson | An array of Alpaca container informations in compressed JSON format |
