param (
    [Parameter(HelpMessage = "The repository of the action", Mandatory = $true)]
    [string] $ActionRepo,
    [Parameter(HelpMessage = "The git ref of the action", Mandatory = $true)]
    [string] $ActionRef
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

$backendUrl = Get-AlpacaBackendUrl
Write-Host "Using Backend Url '$backendUrl'"
Add-Content -encoding UTF8 -Path $env:GITHUB_ENV -Value "ALPACA_BACKEND_URL=$($backendUrl)"
Add-Content -encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "backendUrl=$($backendUrl)"

$scriptsArchiveUrl = "https://github.com/$($ActionRepo)/archive/refs/heads/$($ActionRef).zip"
Write-Host "Using Scripts Archive Url '$scriptsArchiveUrl'"
Add-Content -encoding UTF8 -Path $env:GITHUB_ENV -Value "ALPACA_SCRIPTS_ARCHIVE_URL=$($scriptsArchiveUrl)"
Add-Content -encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "scriptsArchiveUrl=$($scriptsArchiveUrl)"

$scriptsArchiveDirectory = "./Scripts"
Write-Host "Using Scripts Archive Directory '$scriptsArchiveDirectory'"
Add-Content -encoding UTF8 -Path $env:GITHUB_ENV -Value "ALPACA_SCRIPTS_ARCHIVE_DIRECTORY=$($scriptsArchiveDirectory)"
Add-Content -encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "scriptsArchiveDirectory=$($scriptsArchiveDirectory)"
