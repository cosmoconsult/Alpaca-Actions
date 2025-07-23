Param(
    [Hashtable] $parameters
) 

try {
    Write-AlpacaGroupStart "COSMO Alpaca - ImportTestToolkitToBcContainer"

    Write-AlpacaOutput "Importing Test Toolkit to BC Container not necessary for COSMO Alpaca container"
}
finally {
    Write-AlpacaGroupEnd "COSMO Alpaca - ImportTestToolkitToBcContainer"
}

if ($AlGoImportTestToolkitToBcContainer) {
    Write-AlpacaOutput "Invoking AL-Go override"
    Invoke-Command -ScriptBlock $AlGoImportTestToolkitToBcContainer -ArgumentList $parameters
}
