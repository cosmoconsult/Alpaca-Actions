param(
    [Hashtable] $parameters
)

Write-AlpacaOutput "Using COSMO Alpaca override"

Write-AlpacaOutput "Unpublishing BC Container App is currently not supported for Alpaca container, skipping unpublish step"

if ($AlGoUnPublishBcContainerApp) {
    Write-AlpacaOutput "Invoking AL-Go override"
    Invoke-Command -ScriptBlock $AlGoUnPublishBcContainerApp -ArgumentList $parameters
}
