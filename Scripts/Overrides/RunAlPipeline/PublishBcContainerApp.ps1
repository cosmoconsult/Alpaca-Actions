Param(
    [Hashtable]$parameters
)

if ($parameters.appFile.GetType().BaseType.Name -eq 'Array') {
    # Check if current run is installing dependenciy apps
    # Dependency apps are already installed and should be skipped
    $equal = $true
    for ($i = 0; $i -lt $appsBeforeApps.Count; $i++) {
        if ($appsBeforeApps[$i] -ne $parameters.appFile[$i]) {
            $equal = $false
            break
        }
    }

    if (-not $equal) {
        #check second dependency array
        $equal = $true
        for ($i = 0; $i -lt $appsBeforeTestApps.Count; $i++) {
            if ($appsBeforeTestApps[$i] -ne $parameters.appFile[$i]) {
                $equal = $false
                break
            }
        }
    }

    if ($equal) {
        Write-Host "Skip apps before apps/testapps because they are already handled by Alpaca"
        return
    }
}

if (! $env:ALPACA_CONTAINER_READY){
    Write-Host "::group::Wait for image to be ready"
    Wait-AlpacaImageReady -token $env:_token -containerName $env:ALPACA_CONTAINER_ID
    Write-Host "::endgroup::"
    Write-Host "::group::Wait for container start"
    Wait-AlpacaContainerReady -token $env:_token -containerName $env:ALPACA_CONTAINER_ID
    Write-Host "::endgroup::"

    # Set ALPACA_CONTAINER_READY
    Write-Host "Setting ALPACA_CONTAINER_READY to '$true'"
    $env:ALPACA_CONTAINER_READY = $true
} else {
    Write-Host "ALPACA_CONTAINER_READY is already set to '$env:ALPACA_CONTAINER_READY'. Skipping wait."
}

Write-Host "Get password from SecureString"
$password = ConvertFrom-SecureString -SecureString $parameters.bcAuthContext.Password -AsPlainText

Publish-AlpacaBcApp -containerUrl $parameters.Environment `
                    -containerUser $parameters.bcAuthContext.username `
                    -containerPassword $password `
                    -path $parameters.appFile

if ($AlGoPublishBcContainerApp) {
    Write-Host "Invoking AL-Go override"
    Invoke-Command -ScriptBlock $AlGoPublishBcContainerApp -ArgumentList $parameters
}