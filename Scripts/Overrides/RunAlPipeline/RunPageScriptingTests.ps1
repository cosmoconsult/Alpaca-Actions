param(
    [string] $containerName,
    [string] $testCountry
)


Write-Host "Custom Function - RunPageScriptingTests.ps1 - Start"

Write-Host "Custom Code Start"
sudo npx playwright install-deps 
Write-Host "Custom Code End"

RunPageScriptingTests @PSBoundParameters 
Write-Host "Custom Function - RunPageScriptingTests.ps1 - End"



