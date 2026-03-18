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
        $PSBoundParameters.GetEnumerator() | ForEach-Object { 
            $value = if ($_.Value -is [array] -or $_.Value -is [hashtable]) {
                $_.Value | ConvertTo-Json -Compress
            }
            else {
                $_.Value
            }
            Write-AlpacaDebug "$($_.Key): $value"
        }
    }
    finally {
        Write-AlpacaGroupEnd
    }
}

Write-AlpacaOutput "Overriding start address to Environment value: $($environment)" # $environment comes from parent script
$local_startAddress = $environment
Set-Variable -Name 'startAddress' -Value $local_startAddress -Scope 1


Write-AlpacaOutput ("Overriding credential to BcAuthContext credential (User: {0})" -f $(try { $bcAuthContext.username }catch { "" })) # bcAuthContext comes from parent script
$local_credential = New-Object System.Management.Automation.PSCredential ($bcAuthContext.username, $bcAuthContext.Password)
Set-Variable -Name 'credential' -Value $local_credential -Scope 1

Write-AlpacaOutput "Rebuild Param Object with modified parameters"
$UpdatedParams = @{}
$UpdatedParams += $PSBoundParameters.GetEnumerator() | ForEach-Object { @{"$($PSBoundParameters[$_.Key])" = $(Get-Variable -Name $_.Key -ValueOnly) } }
        
Write-AlpacaOutput "Invoking parent RunPageScriptingTests with modified parameters"
RunPageScriptingTests @UpdatedParams # invoke parent
