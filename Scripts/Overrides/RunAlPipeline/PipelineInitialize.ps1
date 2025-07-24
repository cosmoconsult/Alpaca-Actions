param(
    [Parameter(Mandatory = $true)]
    [string] $ScriptsPath,
    [Parameter(Mandatory = $true)]
    [object] $InitializationJob,
    [Parameter(Mandatory = $true)]
    [object] $CreateContainersJob
)

Import-Module (Join-Path $ScriptsPath "Modules/Alpaca.psd1") -Scope Global -DisableNameChecking

Write-AlpacaOutput "Using COSMO Alpaca override"

# Collect informations

Write-AlpacaGroupStart "Collect Informations"

Write-AlpacaOutput "Get AL-Go project from environmental variable"
$project = $env:_project

Write-AlpacaOutput "Get Alpaca backend url from outputs of initialization job"
$backendUrl = $InitializationJob.outputs.backendUrl

Write-AlpacaOutput "Get Alpaca container information from outputs of create containers job"
$containers = @("$($CreateContainersJob.outputs.containersJson)" | ConvertFrom-Json)
$container = $containers | Where-Object { $_.Project -eq $project }
if (! $container) {
    throw "No Alpaca container information for project '$project' found"
}

Write-AlpacaOutput "Get container authentication context from Alpaca container information"
$containerAuthContext = @{
    username = $container.User
    Password = ConvertTo-SecureString -String $container.Password -AsPlainText
}

Write-AlpacaGroupEnd



# Update variables

Write-AlpacaGroupStart "Update Variables"

Write-AlpacaOutput "Set environmental variable 'ALPACA_BACKEND_URL' to '$backendUrl'"
$env:ALPACA_BACKEND_URL = $backendUrl

Write-AlpacaOutput "Set environmental variable 'ALPACA_CONTAINER_ID' to '$($container.Id)'"
$env:ALPACA_CONTAINER_ID = $container.Id

Write-AlpacaOutput "Set parent variable 'bcAuthContext' to '$([pscustomobject]$containerAuthContext)'"
Set-Variable -Name 'bcAuthContext' -value $containerAuthContext -scope 1

Write-AlpacaOutput "Set parent variable 'environment' to '$($container.Url)'"
Set-Variable -Name 'environment' -value $container.Url -scope 1

Write-AlpacaGroupEnd



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
        } else {
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