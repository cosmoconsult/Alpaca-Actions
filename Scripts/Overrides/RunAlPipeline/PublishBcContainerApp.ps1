Param(
    [Hashtable] $parameters
)

Write-AlpacaOutput "Using COSMO Alpaca override"

$outputAppFiles = $apps + $testApps + $bcptTestApps | ForEach-Object { Resolve-Path -Path $_ } | ForEach-Object { Write-AlpacaOutput "- $_"; $_ }
$previousAppFiles = $previousApps | ForEach-Object { Resolve-Path -Path $_ } | ForEach-Object { Write-AlpacaOutput "- $_"; $_ }
$installAppFiles = $installApps + $installTestApps | ForEach-Object { Resolve-Path -Path $_ } | ForEach-Object { Write-AlpacaOutput "- $_"; $_ }

$dependenciesFolder = Join-Path "$env:GITHUB_WORKSPACE" ".dependencies"
$dependencyAppFileHashs = 
    Get-ChildItem -Path $dependenciesFolder -File -Recurse |
    ForEach-Object { Get-FileHash -Path $_ }

Write-AlpacaOutput "Dependencies folder: $dependenciesFolder"
Write-AlpacaOutput "Dependency Apps:"
$dependencyAppFileHashs | ForEach-Object { Write-AlpacaOutput "- $($_.Path): $($_.Hash)"}

$appFiles = @();
$skipAppFiles = @();
$skipAppFileHashs = @();
foreach ($appFile in $parameters.appFile) {
    $appFile = Resolve-Path -Path $appFile
    Write-AlpacaOutput "- - $($outputAppFiles -contains $appFile)"
    if ($outputAppFiles -contains $appFile) {
        # Publish output apps
        $appType = "build output"
    } elseif ($previousAppFiles -contains $appFile) {
        # Publish previous apps
        $appType = "previous release"
    } elseif ($installAppFiles -contains $appFile -and $dependencyAppFileHashs.Hash -contains (Get-FileHash -Path $appFile).Hash) {
        # Publish dependency apps
        $appType = "project dependency"
    } else {
        # Skip remaining apps
        $skipAppFiles += $appFile
        $skipAppFileHashs += (Get-FileHash -Path $appFile)
        continue
    }

    if (! $appFiles) { Write-AlpacaOutput "Apps:" }
    Write-AlpacaOutput "- $appFile ($appType)"
    $appFiles += $appFile
}

if ($skipAppFiles) {
    Write-AlpacaOutput "Skip Apps already handled by COSMO Alpaca:"
    # $skipAppFiles | ForEach-Object { Write-AlpacaOutput "- $_" }
    $skipAppFileHashs | ForEach-Object { Write-AlpacaOutput "- $($_.Path): $($_.Hash)" }
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