param(
    [Hashtable] $parameters
)
Write-AlpacaOutput "Using COSMO Alpaca override"

if ($env:RUNNER_DEBUG -eq "1") {
    Write-AlpacaGroupStart "Parameters"
    try {
        $parameters.GetEnumerator() | ForEach-Object { Write-AlpacaDebug "$($_.Key): $($_.Value)" }
    }
    finally {
        Write-AlpacaGroupEnd
    }
}

Write-AlpacaOutput "Overriding start address to Environment value: $($parameters.Environment)"
$parameters.startAddress = $parameters.Environment

Write-AlpacaOutput ("Overriding credential to BcAuthContext credential (User: {0})" -f $(try { $bcAuthContext.username }catch { "" }))
$parameters.credential = New-Object System.Management.Automation.PSCredential ($bcAuthContext.username, $bcAuthContext.Password)

Write-AlpacaOutput "Invoking parent RunPageScriptingTests with modified parameters"
RunPageScriptingTests $parameters #invoke parent
