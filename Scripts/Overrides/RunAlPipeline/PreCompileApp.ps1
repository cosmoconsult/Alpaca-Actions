param(
    [string] $appType,
    [ref] $compilationParams
)
Write-Host "Hello Alpaca Overwrite"
Invoke-AlpacaPrecompileApp -appType $appType -compilationParams ([ref] $compilationParams)