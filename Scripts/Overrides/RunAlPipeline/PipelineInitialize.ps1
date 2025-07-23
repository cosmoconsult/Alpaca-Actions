param(
    [Parameter(Mandatory = $true)]
    [string] $ScriptsPath,
    [Parameter(Mandatory = $true)]
    [object] $InitializationJob,
    [Parameter(Mandatory = $true)]
    [object] $CreateContainersJob
)

Import-Module (Join-Path $ScriptsPath "Modules\Alpaca.psd1") -Scope Global -DisableNameChecking

# Collect informations

Write-Host "Getting AL-Go project from environmental variable"
$project = $env:_project

Write-Host "Getting Alpaca backend url from initialization job outputs"
$backendUrl = $InitializationJob.outputs.backendUrl

Write-Host "Geting Alpaca container information from create containers job outputs"
$containers = @("$($CreateContainersJob.outputs.containersJson)" | ConvertFrom-Json)
$container = $containers | Where-Object { $_.Project -eq $project }
if (! $container) {
    throw "No Alpaca container information for project '$project' found"
}

Write-Host "Getting Alpaca container authentication context from container information"
$containerAuthContext = @{
    username = $container.User
    Password = ConvertTo-SecureString -String $container.Password -AsPlainText
}

# Set variables

Write-Host "Setting environmental 'ALGO_PROJECT' to '$project'"
$env:ALGO_PROJECT = $project

Write-Host "Setting environmental 'ALPACA_BACKEND_URL' to '$backendUrl'"
$env:ALPACA_BACKEND_URL = $backendUrl

Write-Host "Setting environmental 'ALPACA_CONTAINER_ID' to '$($container.Id)'"
$env:ALPACA_CONTAINER_ID = $container.Id

Write-Host "Setting parent 'bcAuthContext' to '$([pscustomobject]$containerAuthContext)'"
Set-Variable -Name 'bcAuthContext' -value $containerAuthContext -scope 1

Write-Host "Setting parent 'environment' to '$($container.Url)'"
Set-Variable -Name 'environment' -value $container.Url -scope 1

# Initialize packages folder

Write-Host "Get PackagesFolder"
$packagesFolder = CheckRelativePath -baseFolder $baseFolder -sharedFolder $sharedFolder -path $packagesFolder -name "packagesFolder"
if (Test-Path $packagesFolder) {
    Remove-Item $packagesFolder -Recurse -Force
}
New-Item $packagesFolder -ItemType Directory | Out-Null
Write-Host "Packagesfolder is '$packagesFolder'"

Write-Host "Download Alpaca artifacts"
Get-AlpacaDependencyApps -packagesFolder $packagesFolder -token $env:_token

# Load overrides

$alpacaOverrides = $runAlPipelineOverrides | Where-Object { $_ -ne "PipelineInitialize"}
if ($alpacaOverrides) {

    Write-Host "Loading Alpaca overrides"

    $alpacaOverrides | ForEach-Object {
        $scriptName = $_
        $scriptPath = Join-Path $ScriptsPath "Overrides\RunAlPipeline\$scriptName.ps1"

        if (Test-Path -Path $scriptPath -Type Leaf) {
            Write-Host "Getting existing override for '$scriptName'"
            $existingScriptBlock = Get-Variable -Name $scriptName -ValueOnly -Scope 1 -ErrorAction Ignore
            if ($existingScriptBlock) {
                Write-Host -ForegroundColor Yellow "Existing '$scriptName' override"; 
                Write-Host $existingScriptBlock.ToString()

                Write-Host "Setting parent 'AlGo$ScriptName' to existing override"
                Set-Variable -Name "AlGo$scriptName" -Value $existingScriptBlock -Scope 1
            }

            Write-Host "Loading Alpaca override for '$scriptName' with '$scriptPath'"
            $scriptBlock = Get-Command $scriptPath | Select-Object -ExpandProperty ScriptBlock

            Write-Host "Setting parent '$scriptName' to Alpaca override"
            Set-Variable -Name $scriptName -Value $scriptBlock -Scope 1
        }
    }
}