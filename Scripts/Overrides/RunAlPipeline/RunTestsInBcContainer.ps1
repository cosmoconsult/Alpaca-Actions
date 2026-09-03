param(
    [Hashtable] $Parameters
)

Write-AlpacaOutput "Using COSMO Alpaca override"


if ($AlGoRunTestsInBcContainer) {
    Write-AlpacaOutput "Invoking Run-TestsInBcContainer override"
    $runResult = Invoke-Command -ScriptBlock $AlGoRunTestsInBcContainer -ArgumentList $Parameters
}
else {
    Write-AlpacaDebug "Invoking Run-TestsInBcContainer"
    $runResult = Run-TestsInBcContainer @Parameters
}

if ($Parameters.extensionId -eq ($testAppIds.Keys | Select-Object -Last 1)) { # $testAppIds comes from parent scope (Run-AlPipeline)
    $settings = $env:Settings | ConvertFrom-Json
    $alpacaSettings = Get-AlpacaALGoSettings -Settings $settings
    $actionOnMissingTests = [string]$alpacaSettings.actionOnMissingTests

    Write-AlpacaDebug -Message "ExtensionId matches last TestAppId"
    Write-AlpacaDebug -Message "actionOnMissingTests: $actionOnMissingTests"

    if ($actionOnMissingTests -eq 'None') {
        Write-AlpacaDebug -Message "Skipping missing test case check because actionOnMissingTests is None"
        return $runResult
    }

    $testResultsFileName = $Parameters.JUnitResultFileName

    Write-AlpacaDebug -Message "Checking test results file: $testResultsFileName"
    if (-not (Test-Path -Path $testResultsFileName -PathType Leaf)) {
        $message = "Test results file '$testResultsFileName' was not found."
        if ($actionOnMissingTests -eq 'Warning') {
            Write-AlpacaWarning -Message $message
            return $runResult
        }
        throw $message
    }
    [xml]$testResultsXml = Get-Content -Path $testResultsFileName -Raw
    $testCaseNodes = @($testResultsXml.SelectNodes('//testcase'))

    if ($testCaseNodes.Count -lt 1) {
        $message = "Executed $($testAppIds.Count) test app(s), but no test cases were executed."
        if ($actionOnMissingTests -eq 'Warning') {
            Write-AlpacaWarning -Message $message
            return $runResult
        }
        throw $message
    }

    Write-AlpacaDebug -Message "Found $($testCaseNodes.Count) testcase element(s) in test results file"
}

return $runResult


