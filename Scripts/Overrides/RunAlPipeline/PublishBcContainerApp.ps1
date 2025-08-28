Param(
    [Hashtable] $parameters
)

Write-AlpacaOutput "Using COSMO Alpaca override"

$outputAppFiles = $apps + $testApps + $bcptTestApps | Resolve-Path | Select-Object -ExpandProperty Path
$previousAppFiles = $previousApps | Resolve-Path | Select-Object -ExpandProperty Path
$installAppFiles = $installApps + $installTestApps | Resolve-Path | Select-Object -ExpandProperty Path

$dependenciesFolder = Join-Path "$env:GITHUB_WORKSPACE" ".dependencies"
$dependencyAppFileHashs = 
    Get-ChildItem -Path $dependenciesFolder -File -Recurse |
    Where-Object { $installAppFiles -contains $_.FullName } |
    ForEach-Object { (Get-FileHash -Path $_).Hash }

$appFiles = @();
$skipAppFiles = @();
foreach ($appFile in $parameters.appFile) {
    $appFile = (Resolve-Path -Path $appFile).Path
    if ($outputAppFiles -contains $appFile) {
        # Publish output apps
        $appType = "build output"
    } elseif ($previousAppFiles -contains $appFile) {
        # Publish previous apps
        $appType = "previous release"
    } elseif ($dependencyAppFileHashs -contains (Get-FileHash -Path $appFile).Hash) {
        # Publish dependency apps
        $appType = "project dependency"
    } else {
        # Skip remaining apps
        $skipAppFiles += $appFile
        continue
    }

    if (! $appFiles) { Write-AlpacaOutput "Apps:" }
    Write-AlpacaOutput "- $appFile ($appType)"
    $appFiles += $appFile
}

if ($skipAppFiles) {
    Write-AlpacaOutput "Skip Apps already handled by COSMO Alpaca:"
    $skipAppFiles | ForEach-Object { Write-AlpacaOutput "- $_" }
}

if ($appFiles) {
    Write-AlpacaGroupStart "Wait for image to be ready"
    if ($env:ALPACA_CONTAINER_IMAGE_READY) {
        Write-AlpacaOutput "ALPACA_CONTAINER_IMAGE_READY is already set to '$env:ALPACA_CONTAINER_IMAGE_READY'. Skipping wait."
    } else {
        Wait-AlpacaContainerImageReady -Token $env:_token -ContainerName $env:ALPACA_CONTAINER_ID
        Write-AlpacaOutput "Set ALPACA_CONTAINER_IMAGE_READY to '$true'"
        $env:ALPACA_CONTAINER_IMAGE_READY = $true
    }
    Write-AlpacaGroupEnd

    Write-AlpacaGroupStart "Wait for container start"
    if ($env:ALPACA_CONTAINER_READY) {
        Write-AlpacaOutput "ALPACA_CONTAINER_READY is already set to '$env:ALPACA_CONTAINER_READY'. Skipping wait."
    } else {
        Wait-AlpacaContainerReady -Token $env:_token -ContainerName $env:ALPACA_CONTAINER_ID
        Write-AlpacaOutput "Set ALPACA_CONTAINER_READY to '$true'"
        $env:ALPACA_CONTAINER_READY = $true
    }
    Write-AlpacaGroupEnd

    Write-AlpacaOutput "Get password from SecureString"
    $password = ConvertFrom-SecureString -SecureString $parameters.bcAuthContext.Password -AsPlainText

    foreach($appFile in $appFiles) {
        Publish-AlpacaBcApp -ContainerUrl $parameters.Environment `
                            -ContainerUser $parameters.bcAuthContext.username `
                            -ContainerPassword $password `
                            -Path $appFile
    }
}

if ($AlGoPublishBcContainerApp) {
    Write-AlpacaOutput "Invoking AL-Go override"
    Invoke-Command -ScriptBlock $AlGoPublishBcContainerApp -ArgumentList $parameters
}