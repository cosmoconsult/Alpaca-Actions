# Create Alpaca Containers

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

## OUTPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| ALPACA_BACKEND_URL | COSMO Alpaca Backend URL |
| ALPACA_SCRIPTS_ARCHIVE_URL | Url for downloading an Archive containing the COSMO Alpaca Scripts |
| ALPACA_SCRIPTS_ARCHIVE_DIRECTORY | Direcotry inside the Archive that contains the COSMO Alpaca scripts |

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| backendUrl | COSMO Alpaca Backend URL |
| scriptsArchiveUrl | Url for downloading an Archive containing the COSMO Alpaca Scripts |
| scriptsArchiveDirectory | Direcotry inside the Archive that contains the COSMO Alpaca scripts |
