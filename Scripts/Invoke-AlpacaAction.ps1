# Inspired by Invoke-AlGoAction.ps1

param(
    [Parameter(Mandatory = $false)]
    [string] $ActionName = "$($env:GITHUB_ACTION)",
    [Parameter(Mandatory = $true)]
    [scriptblock]$Action,
    [Parameter(Mandatory = $false)]
    [System.Collections.Generic.Dictionary[[System.String], [System.String]]] $AdditionalData = @{}
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
    $startTime = Get-Date

    Invoke-Command -ScriptBlock $Action

    Write-AlpacaDebug "Emit telemetry on successful action run."
    $AdditionalData["ActionDuration"] = (((Get-Date) - $startTime).TotalSeconds).ToString()
    Trace-Information -ActionName $ActionName -AdditionalData $AdditionalData
}
catch {
    Write-AlpacaDebug "Emit telemetry on failed action run."
    $AdditionalData["ActionDuration"] = (((Get-Date) - $startTime).TotalSeconds).ToString()
    Trace-Exception -ActionName $ActionName -ErrorRecord $_ -AdditionalData $AdditionalData

    Write-AlpacaError "Unexpected error when running action '$ActionName':`n$_"
    throw
}