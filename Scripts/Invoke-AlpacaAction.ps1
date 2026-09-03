# Inspired by Invoke-AlGoAction.ps1

param(
    [Parameter(Mandatory = $false)]
    [string] $ActionName = "$($env:GITHUB_ACTION)",
    [Parameter(Mandatory = $true)]
    [scriptblock]$Action
)


$errorActionPreference = "Stop"
$progressPreference = "SilentlyContinue"

if ([string]::IsNullOrWhiteSpace($ActionName)) {
    $ActionName = "Invoke-AlpacaAction"
}

try {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Modules\Alpaca.psd1" -Resolve) -DisableNameChecking
}
catch {
    Write-Host "::ERROR::Unexpected error when running action. Error Message: $($_.Exception.Message.Replace("`r",'').Replace("`n",' ')), StackTrace: $($_.ScriptStackTrace.Replace("`r",'').Replace("`n",' <- '))";
    throw
}

try {
    Invoke-Command -ScriptBlock $Action
}
catch {
    Write-AlpacaError "Unexpected error when running action '$ActionName':`n$_"
    throw
}