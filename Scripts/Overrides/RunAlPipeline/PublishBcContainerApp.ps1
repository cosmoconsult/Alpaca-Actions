Param(
    [Hashtable] $parameters
)

Write-AlpacaOutput "Using COSMO Alpaca override"

$publishedAppInfos = Get-Variable -Name alpacaPublishedAppInfos -ValueOnly -Scope Script -ErrorAction Ignore
if (! $publishedAppInfos) {
    $publishedAppInfos = @()
}

# Collect app files
$outputAppFiles = $apps + $testApps + $bcptTestApps | Resolve-Path | Select-Object -ExpandProperty Path
$previousAppFiles = $previousApps | Resolve-Path | Select-Object -ExpandProperty Path
$installAppFiles = $installApps + ($installTestApps -replace '^\(|\)$') | Resolve-Path | Select-Object -ExpandProperty Path

# Collect parameter app infos
$appInfos = @()
if ($parameters.appFile) {
    $compilerFolder = (GetCompilerFolder)
    $appInfos += GetAppInfo -AppFiles $parameters.appFile -compilerFolder $compilerFolder -cacheAppinfoPath (Join-Path $packagesFolder 'cache_AppInfo.json')
}

# Collect dependency app infos
$dependenciesFolder = Join-Path "$env:GITHUB_WORKSPACE" ".dependencies"
$dependencyAppFiles = @()
$dependencyAppInfos = @()
if (Test-Path $dependenciesFolder) {
    $dependencyAppFiles += Get-ChildItem -Path $dependenciesFolder -File -Recurse |
        Select-Object -ExpandProperty FullName |
        Where-Object { $installAppFiles -contains $_ }
}
if ($dependencyAppFiles) {
    $compilerFolder = (GetCompilerFolder)
    $dependencyAppInfos += GetAppInfo -AppFiles $dependencyAppFiles -compilerFolder $compilerFolder -cacheAppinfoPath (Join-Path $dependenciesFolder 'cache_AppInfo.json')
}

Write-AlpacaGroupStart "Apps:"

$appInfos = $appInfos | ForEach-Object {
    $appInfo = $_
    $appFile = (Resolve-Path -Path $appInfo.Path).Path
    $appLabel = '{0}, {1}, {2}, {3}' -f $appInfo.Id, $appInfo.Name, $appInfo.Publisher, $appInfo.Version

    # Skip unhandled apps
    $appComment = "skip"

    if ($publishedAppInfos | Where-Object { $_.id -eq $appInfo.id -and $_.version -eq $appInfo.version }) {
        # Skip already published apps
        $appComment = "skip already published"
    } elseif ($outputAppFiles -contains $appFile) {
        # Publish output apps
        $appComment = "publish build output"
        $appInfo
    } elseif ($previousAppFiles -contains $appFile) {
        # Publish previous apps
        $appComment = "publish previous release"
        $appInfo
    } elseif ($dependencyAppInfos | Where-Object { $_.id -eq $appInfo.id -and $_.version -eq $appInfo.version }) {
        # Publish dependency apps
        $appComment = "publish dependency build output"
        $appInfo
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
    Set-Variable -Name alpacaPublishedAppInfos -Value $publishedAppInfos -Scope Script
}

if ($AlGoPublishBcContainerApp) {
    Write-AlpacaOutput "Invoking AL-Go override"
    Invoke-Command -ScriptBlock $AlGoPublishBcContainerApp -ArgumentList $parameters
}