Param(
    [Hashtable] $parameters
) 

Write-Host "Importing Test Toolkit to BC Container not necessary for COSMO Alpaca container"

if ($AlGoImportTestToolkitToBcContainer) {
    Write-Host "Invoking AL-Go override"
    Invoke-Command -ScriptBlock $AlGoImportTestToolkitToBcContainer -ArgumentList $parameters
}
