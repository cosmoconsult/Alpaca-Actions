param(
    [string] $appType,
    [ref] $compilationParams
)
Write-Host "Hello from Alpaca Overwrite"

try {
    Write-Host "Invoke Invoke-AlpacaPrecompileApp"
    Invoke-AlpacaPrecompileApp -appType $appType -compilationParams ([ref] $compilationParams)
}
finally {
    Write-Host "Env:"
    Get-ChildItem Env: | ForEach-Object { Write-Host "  $($_.Name): $($_.Value)" }
    Write-Host "Alpaca Cmdlets:"
    Get-Command *Alpaca* | ForEach-Object { Write-Host "  $($_.Name)" }
}

   




