param(
    [string] $appType,
    [ref] $compilationParams
)
Write-AlpacaOutput "Using COSMO Alpaca override"

Invoke-AlpacaPrecompileApp -appType $appType -compilationParams ([ref] $compilationParams)
