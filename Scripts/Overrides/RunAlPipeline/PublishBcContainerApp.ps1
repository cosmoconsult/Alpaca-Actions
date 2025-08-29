Param(
    [Hashtable] $parameters
)

Write-AlpacaOutput "Using COSMO Alpaca override"

$publishedAppInfos = Get-Variable -Name alpacaPublishedAppInfos -ValueOnly -Scope Script -ErrorAction Ignore
if (! $publishedAppInfos) {
    $publishedAppInfos = @()
}

$compilerFolder = (GetCompilerFolder)

$outputAppFiles = $apps + $testApps + $bcptTestApps | Resolve-Path | Select-Object -ExpandProperty Path
$previousAppFiles = $previousApps | Resolve-Path | Select-Object -ExpandProperty Path
$installAppFiles = $installApps + ($installTestApps -replace '^\(|\)$') | Resolve-Path | Select-Object -ExpandProperty Path

$dependenciesFolder = Join-Path "$env:GITHUB_WORKSPACE" ".dependencies"
$dependencyAppFiles = 
    Get-ChildItem -Path $dependenciesFolder -File -Recurse |
    Select-Object -ExpandProperty FullName |
    Where-Object { $installAppFiles -contains $_ }
$dependencyAppInfos = @()
if ($dependencyAppFiles) {
    $dependencyAppInfos += GetAppInfo -AppFiles $dependencyAppFiles -compilerFolder $compilerFolder -cacheAppinfoPath (Join-Path $dependenciesFolder 'cache_AppInfo.json')
}

Write-AlpacaGroupStart "Apps:"

$appFiles = @();
foreach ($appFile in $parameters.appFile) {
    $appFile = (Resolve-Path -Path $appFile).Path

    if ($outputAppFiles -contains $appFile) {
        # Publish output apps
        Write-AlpacaOutput "- publish build output '$appFile'"
        $appFiles += $appFile
        continue
    }
    if ($previousAppFiles -contains $appFile) {
        # Publish previous apps
        Write-AlpacaOutput "- publish previous release '$appFile'"
        $appFiles += $appFile
        continue
    }

    $appInfo = GetAppInfo -AppFiles $appFile -compilerFolder $compilerFolder -cacheAppinfoPath (Join-Path (Split-Path $appFile -Parent) 'cache_AppInfo.json')

    if ($publishedAppInfos | Where-Object { $_.id -eq $appInfo.id -and $_.version -eq $appInfo.version }) {
        # Skip already published apps
        Write-AlpacaOutput "- skip already published '$appFile'"
        continue
    } 
    if ($dependencyAppInfos | Where-Object { $_.id -eq $appInfo.id -and $_.version -eq $appInfo.version }) {
        # Publish dependency apps
        Write-AlpacaOutput "- publish dependency build output '$appFile'"
        $appFiles += $appFile
        continue
    }

    # Skip unhandled apps
    Write-AlpacaOutput "- skip '$appFile'"
}

Write-AlpacaGroupEnd

if ($appInfos) {
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

        $publishedAppInfos = GetAppInfo -AppFiles $appFile -compilerFolder $compilerFolder -cacheAppinfoPath (Join-Path (Split-Path $appFile -Parent) 'cache_AppInfo.json')
    }
}

Set-Variable -Name alpacaPublishedAppInfos -Value $publishedAppInfos -Scope Script

if ($AlGoPublishBcContainerApp) {
    Write-AlpacaOutput "Invoking AL-Go override"
    Invoke-Command -ScriptBlock $AlGoPublishBcContainerApp -ArgumentList $parameters
}