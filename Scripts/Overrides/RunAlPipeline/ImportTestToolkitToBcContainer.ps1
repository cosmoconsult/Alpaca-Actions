Param(
    [Hashtable] $parameters
) 

begin {
    Write-AlpacaGroupStart "ImportTestToolkitToBcContainer"
}

process {
    Write-AlpacaOutput "Importing Test Toolkit to BC Container not necessary for COSMO Alpaca container"
}

end {
    Write-AlpacaGroupEnd

    if ($AlGoImportTestToolkitToBcContainer) {
        Write-AlpacaOutput "Invoking AL-Go override"
        Invoke-Command -ScriptBlock $AlGoImportTestToolkitToBcContainer -ArgumentList $parameters
    }
}
