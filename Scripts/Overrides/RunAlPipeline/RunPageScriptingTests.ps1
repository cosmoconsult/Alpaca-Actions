param(
    [Hashtable] $parameters
) 

Write-Host "Custom Function - RunPageScriptingTests.ps1 - Start"

Write-Host "Custom Code Start"
sudo npx playwright install-deps 
Write-Host "Custom Code End"

RunPageScriptingTests $parameters #invoke parent
Write-Host "Custom Function - RunPageScriptingTests.ps1 - End"



