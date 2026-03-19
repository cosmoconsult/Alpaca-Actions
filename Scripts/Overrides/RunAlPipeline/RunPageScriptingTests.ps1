param(
    [hashtable] $params
)
Write-AlpacaOutput "Using COSMO Alpaca override"

if (Get-AlpacaIsDebugMode) {
    Write-AlpacaGroupStart "Parameters"
    try {
        $params.GetEnumerator() | ForEach-Object {
            $key = [string]$_.Key
            if ($key -match '(?i)(credential|password|token|secret)') {
                $safeValue = '<redacted>'
            }
            else {
                $safeValue = if ($_.Value -is [array] -or $_.Value -is [hashtable]) {
                    $_.Value | ConvertTo-Json -Compress
                }
                else {
                    $_.Value
                }
            }
            Write-AlpacaDebug "$key: $safeValue"
        }
    }
    finally {
        Write-AlpacaGroupEnd
    }
}

Write-AlpacaOutput "Runner OS: $($env:RUNNER_OS)"
if ($env:RUNNER_OS -ne 'Windows') {
    Write-AlpacaOutput "Detected non-Windows OS ($($env:RUNNER_OS)). Installing necessary dependencies..."
    
    Write-AlpacaOutput "Installing @microsoft/bc-replay"
    pwsh -command { npm i @microsoft/bc-replay@0.1.119 --save --silent }
    Write-AlpacaOutput "Installing Playwright with dependencies"
    pwsh -command { npx playwright install --with-deps chromium }
}

Write-AlpacaOutput "Overriding start address to Environment value: $($environment)" # $environment comes from parent script
$params.startAddress = $environment # modify the hashtable parameter

Write-AlpacaOutput ("Overriding credential to BcAuthContext credential (User: {0})" -f $(try { $bcAuthContext.username }catch { "" })) # bcAuthContext comes from parent script
$params.credential = New-Object System.Management.Automation.PSCredential ($bcAuthContext.username, $bcAuthContext.Password) # modify the hashtable parameter
        
Write-AlpacaOutput "Invoking parent RunPageScriptingTests with modified parameters"
RunPageScriptingTests @params # invoke parent
