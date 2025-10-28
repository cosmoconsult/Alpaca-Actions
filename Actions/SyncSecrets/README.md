# Sync Secrets

Sync COSMO Alpaca secrets to the Alpaca backend for development containers

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
| secretsJson | Yes | An object of key-value pairs representing the secrets to sync | |

## OUTPUT

### ENV variables

none

### OUTPUT variables

none
