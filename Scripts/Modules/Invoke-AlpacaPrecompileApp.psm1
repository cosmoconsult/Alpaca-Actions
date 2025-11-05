param(
    [string] $appType,
    [ref] $compilationParams
)
Write-Host "Hello from Invoke-AlpacaPrecompileApp.psm1"

Export-ModuleMember -Function Invoke-AlpacaPrecompileApp