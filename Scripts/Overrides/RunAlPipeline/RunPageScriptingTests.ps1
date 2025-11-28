param(
    [string] $containerName,
    [PSCredential] $credential,
    [array] $pageScriptingTests,
    [array] $restoreDatabases,
    [string] $pageScriptingTestResultsFile,
    [string] $pageScriptingTestResultsFolder,
    [string] $startAddress,
    [scriptblock] $RestoreDatabasesInBcContainer,
    [switch] $returnTrueIfAllPassed
)
Write-AlpacaOutput "Using COSMO Alpaca override"

if ($env:RUNNER_DEBUG -eq "1") {
    Write-AlpacaGroupStart "Parameters"
    try {
        $PSBoundParameters.GetEnumerator() | ForEach-Object { Write-AlpacaDebug "$($_.Key): $($_.Value)" }
    }
    finally {
        Write-AlpacaGroupEnd
    }
}

Write-AlpacaOutput "Overriding start address to Environment value: $($environment)" # $environment comes from parent script
$startAddress = $environment

Write-AlpacaOutput ("Overriding credential to BcAuthContext credential (User: {0})" -f $(try { $bcAuthContext.username }catch { "" })) # bcAuthContext comes from parent script
$credential = New-Object System.Management.Automation.PSCredential ($bcAuthContext.username, $bcAuthContext.Password)

Write-AlpacaOutput "Rebuild Param Object with modified parameters"
$UpdatedParams = @{}
$UpdatedParams += $PSBoundParameters.GetEnumerator() | ForEach-Object { @{"$($PSBoundParameters[$_.Key])" = $(Get-Variable -Name $_.Key -ValueOnly) } }
        
Write-AlpacaOutput "Invoking parent RunPageScriptingTests with modified parameters"
RunPageScriptingTests @UpdatedParams # invoke parent
