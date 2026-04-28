param(
    [Parameter(Mandatory = $true)]
    [hashtable] $Jobs,
    [Parameter(Mandatory = $true)]
    [string] $ScriptsPath
)

Import-Module (Join-Path $ScriptsPath "Modules/Alpaca.psd1") -Scope Global -DisableNameChecking

function ConvertTo-AlpacaSecurePassword {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Password value is a runtime secret provided by AL-Go, not a literal plaintext string')]
    param([string] $PlainText)
    return ConvertTo-SecureString -String $PlainText -AsPlainText
}

# Collect informations

Write-AlpacaGroupStart "Collect Informations"

Write-AlpacaOutput "Get AL-Go project from environmental variable"
$project = $env:_project

Write-AlpacaOutput "Get AL-Go build mode from environmental variable"
$BuildMode = $env:_buildMode
Write-AlpacaOutput "BuildMode is '$BuildMode'"

Write-AlpacaOutput "Get Alpaca backend url from outputs of initialization job"
$backendUrl = $Jobs.initialization.outputs.backendUrl

Write-AlpacaGroupStart "Create Alpaca container if missing"
$Settings = $env:Settings | ConvertFrom-Json
if ((Get-IsAlpacaContainerRequired -Settings $Settings)) {
    Write-AlpacaOutput "Alpaca container is required based on settings"
    $container = Get-AlpacaContainer -alGoProject $project -Token $env:_token -alGoBuildMode $BuildMode
    if ($container) {
        Write-AlpacaOutput "Container already exists with ID '$($container.id)'. Skipping creation."
    }
    else {
        Write-AlpacaOutput "Creating new Alpaca container for project '$project' and build mode '$BuildMode'"
        $container = New-AlpacaContainer -Project $project -Token $env:_token -BuildMode $BuildMode
    }
}
else {
    Write-AlpacaOutput "No Alpaca container required based on settings"
}
Write-AlpacaGroupEnd

Write-AlpacaOutput "Set Variables based on received container information"
if (! $container) {
    Write-AlpacaOutput "No Alpaca container information for project '$project' and build mode '$BuildMode' found"
    $container = @{
        id       = "NOCONTAINER"
        username = "NOCONTAINER"
        password = "NOCONTAINER"
        weburl   = "https://NOCONTAINER"
    }
}

Write-AlpacaDebug "Container information: $($container | ConvertTo-Json -Depth 10 -Compress)"

Write-AlpacaOutput "Get container authentication context from Alpaca container information"
$containerAuthContext = @{
    username = $container.username
    Password = ConvertTo-AlpacaSecurePassword -PlainText $container.password
}

Write-AlpacaGroupEnd



# Update variables

Write-AlpacaGroupStart "Update Variables"

Write-AlpacaOutput "Set environmental variable 'ALPACA_BACKEND_URL' to '$backendUrl'"
$env:ALPACA_BACKEND_URL = $backendUrl

Write-AlpacaOutput "Set environmental variable 'ALPACA_CONTAINER_ID' to '$($container.id)'"
$env:ALPACA_CONTAINER_ID = $container.id

Write-AlpacaOutput "Set parent variable 'bcAuthContext' to '$([pscustomobject]$containerAuthContext)'"
Set-Variable -Name 'bcAuthContext' -Value $containerAuthContext -Scope 1

Write-AlpacaOutput "Set parent variable 'environment' to '$($container.weburl)'"
Set-Variable -Name 'environment' -Value $container.weburl -Scope 1

Write-AlpacaGroupEnd



# Check Settings

if ($additionalCountries -is [String]) { $additionalCountries = @($additionalCountries.Split(',').Trim() | Where-Object { $_ }) }
if ($additionalCountries.Length -gt 0) {
    Write-AlpacaDebug "Additional countries specified: $($additionalCountries -join ', ')"
    throw "The AL-Go setting 'additionalCountries' is not supported by COSMO Alpaca. Use 'buildModes' to validate additional countries instead. https://docs.cosmoconsult.com/en-en/cloud-service/alpaca/github/"
}

# Initialize Packages Folder

Write-AlpacaGroupStart "Initialize Packages Folder"

Write-AlpacaOutput "Get PackagesFolder"
$packagesFolder = CheckRelativePath -baseFolder $baseFolder -sharedFolder $sharedFolder -path $packagesFolder -name "packagesFolder"
if (Test-Path $packagesFolder) {
    Remove-Item $packagesFolder -Recurse -Force
}
New-Item $packagesFolder -ItemType Directory | Out-Null
Write-AlpacaOutput "Packagesfolder is '$packagesFolder'"

Write-AlpacaOutput "Download Alpaca artifacts"
Get-AlpacaDependencyApps -packagesFolder $packagesFolder -token $env:_token

Write-AlpacaGroupEnd

# Load overrides

Write-AlpacaGroupStart "Load Overrides"

$overridesPath = Join-Path $ScriptsPath "Overrides/RunAlPipeline"

Write-AlpacaOutput "Load Alpaca overrides from $(Resolve-Path $overridesPath -Relative)"

Get-Item -Path $overridesPath |
Get-ChildItem -Filter "*.ps1" -Exclude "PipelineInitialize.*" -File |
ForEach-Object {
    $scriptPath = $_.FullName
    $scriptName = $_.BaseName

    Write-AlpacaGroupStart "Load Alpaca override for '$scriptName'"

    Write-AlpacaOutput "Get Alpaca override from file '$(Resolve-Path $scriptPath -Relative)'"
    $scriptBlock = Get-Command $scriptPath | Select-Object -ExpandProperty ScriptBlock

    Write-AlpacaGroupStart "Get existing override from variable '$scriptName'"
    $existingScriptBlock = Get-Variable -Name $scriptName -ValueOnly -Scope 1 -ErrorAction Ignore
    if ($existingScriptBlock) {
        Write-AlpacaOutput $existingScriptBlock.ToString()
    }
    else {
        Write-AlpacaOutput "None"
    }
    Write-AlpacaGroupEnd

    Write-AlpacaOutput "Set parent variable '$scriptName' to Alpaca override"
    Set-Variable -Name $scriptName -Value $scriptBlock -Scope 1

    Write-AlpacaOutput "Set parent variable 'AlGo$ScriptName' to existing override"
    Set-Variable -Name "AlGo$scriptName" -Value $existingScriptBlock -Scope 1

    Write-AlpacaGroupEnd
}

Write-AlpacaGroupEnd
