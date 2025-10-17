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
$previousAppFiles = $previousApps | Resolve-Path -ea SilentlyContinue | Select-Object -ExpandProperty Path
$installAppFiles = $installApps + ($installTestApps -replace '^\(|\)$') | Resolve-Path -ea SilentlyContinue | Select-Object -ExpandProperty Path

# Extract Files recursively
function GetAppFiles($appFiles, $folder) {
    # Inspired by InitializeModule of bccontainerhelper
    $isPsCore = $PSVersionTable.PSVersion -ge "6.0.0"
    if ($isPsCore) {
        $byteEncodingParam = @{ "asByteStream" = $true }
    }
    else {
        $byteEncodingParam = @{ "Encoding" = "byte" }
    }

    # Inspired by CopyAppFilesToFolder of bccontainerhelper
    if ($appFiles -is [String]) {
        if (!(Test-Path $appFiles)) {
            $appFiles = @($appFiles.Split(',').Trim() | Where-Object { $_ })
        }
    }
    $appFiles | Where-Object { $_ } | ForEach-Object {
        $appFile = "$_"

        if (Test-Path $appFiles -PathType Container) {
            Get-ChildItem $appFiles -Recurse -File | ForEach-Object {
                GetAppFiles -appFiles $_.FullName -folder $folder
            }
        }
        elseif (Test-Path $appFiles -PathType Leaf) {
            Get-ChildItem $appFiles | ForEach-Object {
                $appFile = $_.FullName
                if ($appFile -like "*.app") {
                    $destFileName = [System.IO.Path]::GetFileName($appFile)
                    $destFile = Join-Path $folder $destFileName
                    if ((Test-Path $destFile) -and ((Get-FileHash -Path $appFile).Hash -ne (Get-FileHash -Path $destFile).Hash)) {
                        Write-AlpacaWarning -Message "$destFileName already exists, it looks like you have multiple app files with the same name. App filenames must be unique."
                    }
                    Copy-Item -Path $appFile -Destination $destFile -Force
                    $destFile
                }
                elseif ([string]::new([char[]](Get-Content $appFile @byteEncodingParam -TotalCount 2)) -eq "PK") {
                    $tmpFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
                    $copied = $false
                    try {
                        if ($appFile -notlike "*.zip") {
                            $orgAppFile = $appFile
                            $appFile = Join-Path ([System.IO.Path]::GetTempPath()) "$([System.IO.Path]::GetFileName($orgAppFile)).zip"
                            Copy-Item $orgAppFile $appFile
                            $copied = $true
                        }
                        Expand-Archive $appfile -DestinationPath $tmpFolder -Force
                        GetAppFiles -appFiles $tmpFolder -folder $folder
                    }
                    finally {
                        Remove-Item -Path $tmpFolder -Recurse -Force
                        if ($copied) { Remove-Item -Path $appFile -Force }
                    }
                }
            }
        } 
    }
}



# Collect parameter app infos
$appInfos = @()
if ($parameters.appFile) {
    $compilerFolder = (GetCompilerFolder)

    $appFiles = @()
    $appFiles += GetAppFiles -appFiles $parameters.appFile -folder $TempDir
    foreach ($appFile in $appFiles) {
        $appInfos += GetAppInfo -AppFiles $appFile -compilerFolder $compilerFolder -cacheAppinfoPath (Join-Path $TempDir 'cache_AppInfo.json')
    }
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
    
    $appFiles = @()
    $appFiles += GetAppFiles -appFiles $dependencyAppFiles -folder $TempDir
    foreach ($appFile in $appFiles) {
        $dependencyAppInfos += GetAppInfo -AppFiles $appFile -compilerFolder $compilerFolder -cacheAppinfoPath (Join-Path $dependenciesFolder 'cache_AppInfo.json')
    }
}

Write-AlpacaGroupStart "Apps:"

$appInfos = $appInfos | ForEach-Object {
    $appInfo = $_
    $appFile = (Resolve-Path -Path $appInfo.Path).Path
    $appLabel = '{0}, {1}, {2}, {3}' -f $appInfo.Id, $appInfo.Name, $appInfo.Publisher, $appInfo.Version

    # Skip unhandled apps
    $appComment = "skip"

    if ($publishedAppInfos | Where-Object { $_.Id -eq $appInfo.Id -and $_.Version -eq $appInfo.Version }) {
        # Skip already published apps
        $appComment = "skip already published"
    }
    elseif ($outputAppFiles -contains $appFile) {
        # Publish output apps
        $appComment = "publish build output"
        $appInfo
    }
    elseif ($previousAppFiles -contains $appFile) {
        # Publish previous apps
        $appComment = "publish previous release"
        $appInfo
    }
    elseif ($dependencyAppInfos | Where-Object { $_.Id -eq $appInfo.Id -and $_.Version -eq $appInfo.Version }) {
        # Publish dependency apps
        $appComment = "publish dependency build output"
        $appInfo
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
    $TempDir | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}