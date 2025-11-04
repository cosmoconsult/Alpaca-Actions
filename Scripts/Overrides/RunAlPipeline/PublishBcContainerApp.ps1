Param(
    [Hashtable] $parameters
)

Write-AlpacaOutput "Using COSMO Alpaca override"

#Create and Prepare TempDir
$TempDir = join-path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -Path $TempDir -ItemType Directory -ErrorAction SilentlyContinue | Out-Null

Write-AlpacaGroupStart "Wait for image to be ready"
if ($env:ALPACA_CONTAINER_IMAGE_READY) {
    Write-AlpacaOutput "ALPACA_CONTAINER_IMAGE_READY is already set to '$env:ALPACA_CONTAINER_IMAGE_READY'. Skipping wait."
}
else {
    Wait-AlpacaContainerImageReady -Token $env:_token -ContainerName $env:ALPACA_CONTAINER_ID
    Write-AlpacaOutput "Set ALPACA_CONTAINER_IMAGE_READY to '$true'"
    $env:ALPACA_CONTAINER_IMAGE_READY = $true
}
Write-AlpacaGroupEnd

Write-AlpacaGroupStart "Wait for container to be ready"
if ($env:ALPACA_CONTAINER_READY) {
    Write-AlpacaOutput "ALPACA_CONTAINER_READY is already set to '$env:ALPACA_CONTAINER_READY'. Skipping wait."
}
else {
    Wait-AlpacaContainerReady -Token $env:_token -ContainerName $env:ALPACA_CONTAINER_ID
    Write-AlpacaOutput "Set ALPACA_CONTAINER_READY to '$true'"
    $env:ALPACA_CONTAINER_READY = $true
}
Write-AlpacaGroupEnd

$publishedAppInfos = Get-Variable -Name alpacaPublishedAppInfos -ValueOnly -Scope Script -ErrorAction Ignore
if (! $publishedAppInfos) {
    try {
        $publishedAppInfos = Get-AlpacaAppInfo -Token $env:_token -ContainerName $env:ALPACA_CONTAINER_ID
    }
    catch {
        Write-AlpacaOutput "Error occurred while getting published app infos: $_"
        $publishedAppInfos = @()
    }
}

# Collect app files
$outputAppFiles = $apps + $testApps + $bcptTestApps | Resolve-Path -ea SilentlyContinue | Select-Object -ExpandProperty Path

# Collect parameter app infos
$appInfos = @()
if ($parameters.appFile) {
    $compilerFolder = (GetCompilerFolder)

    $appFiles = @()
    $appFiles += CopyAppFilesToFolder -appFiles $parameters.appFile -folder $TempDir
    foreach ($appFile in $appFiles) {
        $appInfos += GetAppInfo -AppFiles $appFile -compilerFolder $compilerFolder
    }
}

Write-AlpacaGroupStart "Apps:"

$appInfos = $appInfos | ForEach-Object {
    $appInfo = $_
    $appFile = (Resolve-Path -Path $appInfo.Path).Path
    $appLabel = '{0}, {1}, {2}, {3}' -f $appInfo.Id, $appInfo.Name, $appInfo.Publisher, $appInfo.Version

    # Skip unhandled apps
    $appComment = "skip"

    if ($outputAppFiles -contains $appFile) {
        $appComment = "publish build output"
        $appInfo
    }
    else {
        $publishedAppInfo = $publishedAppInfos | Where-Object { $_.Id -eq $appInfo.Id } | Sort-Object { [Version]$_.Version } | Select-Object -Last 1
        if (!$publishedAppInfo) {
            $appComment = "publish new app"
            $appInfo
        }
        else {
            $appComment = "skip - app already installed with version $($publishedAppInfo.Version)"
        }
    }

    Write-AlpacaOutput "- $appComment '$appFile' ($appLabel)"
}

Write-AlpacaGroupEnd

if ($appInfos) {
    $password = ConvertFrom-SecureString -SecureString $parameters.bcAuthContext.Password -AsPlainText

    foreach ($appInfo in $appInfos) {
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

if (Test-Path "$TempDir") {
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}