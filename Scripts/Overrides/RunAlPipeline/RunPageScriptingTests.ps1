param(
    [hashtable] $params
)
Write-AlpacaOutput "Using COSMO Alpaca override"

if ($env:RUNNER_DEBUG -eq "1") {
    Write-AlpacaGroupStart "Parameters"
    try {
        $params.GetEnumerator() | ForEach-Object { 
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
Set-Variable -Name 'startAddress' -Value $environment -Scope 1 # directly modify the variable in the parent scope

Write-AlpacaOutput ("Overriding credential to BcAuthContext credential (User: {0})" -f $(try { $bcAuthContext.username }catch { "" })) # bcAuthContext comes from parent script
$params.credential = New-Object System.Management.Automation.PSCredential ($bcAuthContext.username, $bcAuthContext.Password) # modify the hashtable parameter
        
Write-AlpacaOutput "Invoking parent RunPageScriptingTests with modified parameters: $($params | ConvertTo-Json -Compress)"
RunPageScriptingTests @params # invoke parent
