Param(
    [Hashtable] $parameters
) 

Write-AlpacaOutput "Using COSMO Alpaca override"
Write-AlpacaOutput "Importing Test Toolkit to BC Container not necessary for COSMO Alpaca container"

if ($AlGoImportTestToolkitToBcContainer) {
    Write-AlpacaOutput "Invoking AL-Go override"
    Invoke-Command -ScriptBlock $AlGoImportTestToolkitToBcContainer -ArgumentList $parameters
}
