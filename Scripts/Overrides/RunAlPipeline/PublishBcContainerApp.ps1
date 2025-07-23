Param(
    [Hashtable] $parameters
)

begin {
    Write-AlpacaGroupStart "PublishBcContainerApp"
}

process {
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
    if ($env:ALPACA_IMAGE_READY) {
        Write-AlpacaOutput "ALPACA_IMAGE_READY is already set to '$env:ALPACA_IMAGE_READY'. Skipping wait."
    } else {
        Wait-AlpacaImageReady -token $env:_token -containerName $env:ALPACA_CONTAINER_ID
        Write-AlpacaOutput "Setting ALPACA_IMAGE_READY to '$true'"
        $env:ALPACA_IMAGE_READY = $true
    }
    Write-AlpacaGroupEnd

    Write-AlpacaGroupStart "Wait for container start"
    if ($env:ALPACA_CONTAINER_READY) {
        Write-AlpacaOutput "ALPACA_CONTAINER_READY is already set to '$env:ALPACA_CONTAINER_READY'. Skipping wait."
    } else {
        Wait-AlpacaContainerReady -token $env:_token -containerName $env:ALPACA_CONTAINER_ID
        Write-AlpacaOutput "Setting ALPACA_CONTAINER_READY to '$true'"
        $env:ALPACA_CONTAINER_READY = $true
    }
    Write-AlpacaGroupEnd

    Write-AlpacaOutput "Get password from SecureString"
    $password = ConvertFrom-SecureString -SecureString $parameters.bcAuthContext.Password -AsPlainText

    Publish-AlpacaBcApp -containerUrl $parameters.Environment `
                        -containerUser $parameters.bcAuthContext.username `
                        -containerPassword $password `
                        -path $parameters.appFile
}

end {
    Write-AlpacaGroupEnd

    if ($AlGoPublishBcContainerApp) {
        Write-AlpacaOutput "Invoking AL-Go override"
        Invoke-Command -ScriptBlock $AlGoPublishBcContainerApp -ArgumentList $parameters
    }
}