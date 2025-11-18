param(
    [Hashtable] $parameters
) 

Write-Host "Custom Function - RunPageScriptingTests.ps1 - Start"

Write-AlpacaGroupStart "Parameters"
$parameters.GetEnumerator() | ForEach-Object { Write-AlpacaOutput "$($_.Key): $($_.Value)" }
Write-AlpacaGroupEnd



Write-Host "Custom Code Start"
Write-Host "[exec]sudo npx playwright@1.48.0 install-deps "
sudo npx playwright@1.48.0 install-deps 
Write-Host "[exec]pwsh -command { npm i @microsoft/bc-replay@0.1.67 --save }"
pwsh -command { npm i @microsoft/bc-replay@0.1.67 --save }
Write-AlpacaGroupStart "Debugging Info"
Write-AlpacaOutput "Current Directory: $(Get-Location)"
Write-AlpacaGroupStart "Listing Files:"
Get-ChildItem -Recurse | ForEach-Object { Write-AlpacaOutput $_.FullName }
Write-AlpacaGroupEnd
Write-AlpacaGroupEnd

Write-Host "Custom Code End"




$parameters.startAddress = $parameters.Environment
RunPageScriptingTests $parameters #invoke parent
Write-Host "Custom Function - RunPageScriptingTests.ps1 - End"



