param(
    [Hashtable] $parameters
) 

Write-Host "Custom Function - RunPageScriptingTests.ps1 - Start"

Write-AlpacaGroupStart "Parameters"
$parameters.GetEnumerator() | ForEach-Object { Write-Host "$($_.Key): $($_.Value)" }
Write-AlpacaGroupEnd

Write-Host "Custom Code Start"
sudo npx playwright install-deps 
Write-Host "Custom Code End"

$parameters.startAddress = $parameters.Environment
RunPageScriptingTests $parameters #invoke parent
Write-Host "Custom Function - RunPageScriptingTests.ps1 - End"



