param(
    [Hashtable] $parameters
) 

Write-AlpacaOutput "Custom Function - RunPageScriptingTests.ps1 - Start"

Write-AlpacaGroupStart "Parameters"
$parameters.GetEnumerator() | ForEach-Object { Write-AlpacaOutput "$($_.Key): $($_.Value)" }
Write-AlpacaGroupEnd

Write-AlpacaOutput "Custom Code Start"

# Write-Host "[exec]sudo npx playwright@1.48.0 install-deps "
# sudo npx playwright@1.48.0 install-deps 
# Write-Host "[exec]pwsh -command { npm i @microsoft/bc-replay@0.1.67 --save }"
# pwsh -command { npm i @microsoft/bc-replay@0.1.67 --save }
# Write-AlpacaGroupStart "Debugging Info"
# Write-AlpacaOutput "Current Directory: $(Get-Location)"
# Write-AlpacaGroupStart "Listing Files:"
# Get-ChildItem -Recurse | ForEach-Object { Write-AlpacaOutput $_.FullName }
# Write-AlpacaGroupEnd
# Write-AlpacaGroupEnd

Write-AlpacaOutput "Custom Code End"



Write-AlpacaOutput "Overriding start address to Environment value: $($parameters.Environment)"
$parameters.startAddress = $parameters.Environment

Write-AlpacaOutput ("Overriding credential to BcAuthContext credential (User: {0})" -f $(try { $bcAuthContext.username }catch { "" }))
$parameters.credential = New-Object System.Management.Automation.PSCredential ($bcAuthContext.username, (ConvertTo-SecureString $bcAuthContext.Password -AsPlainText -Force))

Write-AlpacaOutput "Invoking parent RunPageScriptingTests with modified parameters"
RunPageScriptingTests $parameters #invoke parent
Write-AlpacaOutput "Custom Function - RunPageScriptingTests.ps1 - End"



