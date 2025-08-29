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

$appInfos = @();
foreach ($appFile in $parameters.appFile) {
    $appFile = (Resolve-Path -Path $appFile).Path
    $appInfo = GetAppInfo -AppFiles $appFile -compilerFolder $compilerFolder -cacheAppinfoPath (Join-Path (Split-Path $appFile -Parent) 'cache_AppInfo.json')
    $appLabel = '{0}, {1}, {2}, {3}' -f $appInfo.Publisher, $appInfo.Name, $appInfo.Id, $appInfo.Version

    # Skip unhandled apps
    $appComment = "skip"

    if ($publishedAppInfos | Where-Object { $_.id -eq $appInfo.id -and $_.version -eq $appInfo.version }) {
        # Skip already published apps
        $appComment = "skip already published"
    } elseif ($outputAppFiles -contains $appFile) {
        # Publish output apps
        $appComment = "publish build output"
        $appInfos += $appInfo
    } elseif ($previousAppFiles -contains $appFile) {
        # Publish previous apps
        $appComment = "publish previous release"
        $appInfos += $appInfo
    } elseif ($dependencyAppInfos | Where-Object { $_.id -eq $appInfo.id -and $_.version -eq $appInfo.version }) {
        # Publish dependency apps
        $appComment = "publish dependency build output"
        $appInfos += $appInfo
    }

    Write-AlpacaOutput "- $appComment '$appFile' ($appLabel)"
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

    foreach($appInfo in $appInfos) {
        Publish-AlpacaBcApp -ContainerUrl $parameters.Environment `
                            -ContainerUser $parameters.bcAuthContext.username `
                            -ContainerPassword $password `
                            -Path $appInfo.Path
    }

    $publishedAppInfos += $appInfos
}

Set-Variable -Name alpacaPublishedAppInfos -Value $publishedAppInfos -Scope Script

if ($AlGoPublishBcContainerApp) {
    Write-AlpacaOutput "Invoking AL-Go override"
    Invoke-Command -ScriptBlock $AlGoPublishBcContainerApp -ArgumentList $parameters
}