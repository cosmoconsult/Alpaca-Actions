Param(
    [Hashtable] $parameters
)

try {
    Write-AlpacaGroupStart "COSMO Alpaca - PublishBcContainerApp"

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
            Write-AlpacaOutput "Skip apps before apps/testapps because they are already handled by Alpaca"
            return
        }
    }

    Write-AlpacaGroupStart "Wait for image to be ready"
    if ($env:ALPACA_CONTAINER_IMAGE_READY) {
        Write-AlpacaOutput "ALPACA_CONTAINER_IMAGE_READY is already set to '$env:ALPACA_CONTAINER_IMAGE_READY'. Skipping wait."
    } else {
        Wait-AlpacaContainerImageReady -Token $env:_token -ContainerName $env:ALPACA_CONTAINER_ID
        Write-AlpacaOutput "Setting ALPACA_CONTAINER_IMAGE_READY to '$true'"
        $env:ALPACA_CONTAINER_IMAGE_READY = $true
    }
    Write-AlpacaGroupEnd

    Write-AlpacaGroupStart "Wait for container start"
    if ($env:ALPACA_CONTAINER_READY) {
        Write-AlpacaOutput "ALPACA_CONTAINER_READY is already set to '$env:ALPACA_CONTAINER_READY'. Skipping wait."
    } else {
        Wait-AlpacaContainerReady -Token $env:_token -ContainerName $env:ALPACA_CONTAINER_ID
        Write-AlpacaOutput "Setting ALPACA_CONTAINER_READY to '$true'"
        $env:ALPACA_CONTAINER_READY = $true
    }
    Write-AlpacaGroupEnd

    Write-AlpacaOutput "Get password from SecureString"
    $password = ConvertFrom-SecureString -SecureString $parameters.bcAuthContext.Password -AsPlainText

    Publish-AlpacaBcApp -ContainerUrl $parameters.Environment `
                        -ContainerUser $parameters.bcAuthContext.username `
                        -ContainerPassword $password `
                        -Path $parameters.appFile
}
finally {
    Write-AlpacaGroupEnd
}

if ($AlGoPublishBcContainerApp) {
    Write-AlpacaOutput "Invoking AL-Go override"
    Invoke-Command -ScriptBlock $AlGoPublishBcContainerApp -ArgumentList $parameters
}