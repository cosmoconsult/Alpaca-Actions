Param(
    [Hashtable] $parameters
)

Write-AlpacaOutput "Using COSMO Alpaca override"

$publishedAppFiles = Get-Variable -Name alpacaPublishedAppFiles -ValueOnly -Scope 1 -ErrorAction Ignore
if (! $publishedAppFiles) {
    $publishedAppFiles = @()
}

$outputAppFiles = $apps + $testApps + $bcptTestApps | Resolve-Path | Select-Object -ExpandProperty Path
$previousAppFiles = $previousApps | Resolve-Path | Select-Object -ExpandProperty Path
$installAppFiles = $installApps + ($installTestApps -replace '^\(|\)$') | Resolve-Path | Select-Object -ExpandProperty Path

$dependenciesFolder = Join-Path "$env:GITHUB_WORKSPACE" ".dependencies"
$dependencyAppFileHashs = 
    Get-ChildItem -Path $dependenciesFolder -File -Recurse |
    Where-Object { $installAppFiles -contains $_.FullName } |
    ForEach-Object { (Get-FileHash -Path $_).Hash }

Write-AlpacaGroupStart "Publish Apps:"

$appFiles = @();
$skipAppFiles = @();
foreach ($appFile in $parameters.appFile) {
    $appFile = (Resolve-Path -Path $appFile).Path

    if ($publishedAppFiles -contains $appFile) {
        # Skip already published apps
        $skipAppFiles += $appFile
    } elseif ($outputAppFiles -contains $appFile) {
        # Publish output apps
        Write-AlpacaOutput "- $appFile (build output)"
        $appFiles += $appFile
    } elseif ($previousAppFiles -contains $appFile) {
        # Publish previous apps
        Write-AlpacaOutput "- $appFile (previous release)"
        $appFiles += $appFile
    } elseif ($dependencyAppFileHashs -contains (Get-FileHash -Path $appFile).Hash) {
        # Publish dependency apps
        Write-AlpacaOutput "- $appFile (project dependency)"
        $appFiles += $appFile
    } else {
        # Skip remaining apps
        $skipAppFiles += $appFile
    }
}

if (! $appFiles) {
    Write-AlpacaOutput "- None"
}

Write-AlpacaGroupEnd

if ($skipAppFiles) {
    Write-AlpacaGroupStart "Skip Apps:"
    $skipAppFiles | ForEach-Object { Write-AlpacaOutput "- $_" }
    Write-AlpacaGroupEnd
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

    Write-AlpacaGroupStart "Wait for container to be ready"
    if ($env:ALPACA_CONTAINER_READY) {
        Write-AlpacaOutput "ALPACA_CONTAINER_READY is already set to '$env:ALPACA_CONTAINER_READY'. Skipping wait."
    } else {
        Wait-AlpacaContainerReady -Token $env:_token -ContainerName $env:ALPACA_CONTAINER_ID
        Write-AlpacaOutput "Set ALPACA_CONTAINER_READY to '$true'"
        $env:ALPACA_CONTAINER_READY = $true
    }
    Write-AlpacaGroupEnd

    $password = ConvertFrom-SecureString -SecureString $parameters.bcAuthContext.Password -AsPlainText

    foreach($appFile in $appFiles) {
        Publish-AlpacaBcApp -ContainerUrl $parameters.Environment `
                            -ContainerUser $parameters.bcAuthContext.username `
                            -ContainerPassword $password `
                            -Path $appFile
    }

    $publishedAppFiles += $appFiles
}

Set-Variable -Name alpacaPublishedAppFiles -Value $publishedAppFiles -Scope 1

if ($AlGoPublishBcContainerApp) {
    Write-AlpacaOutput "Invoking AL-Go override"
    Invoke-Command -ScriptBlock $AlGoPublishBcContainerApp -ArgumentList $parameters
}