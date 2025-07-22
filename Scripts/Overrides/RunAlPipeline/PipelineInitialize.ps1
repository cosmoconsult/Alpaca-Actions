param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptsPath,
    [Parameter(Mandatory = $true)]
    [object]$InitializationJob,
    [Parameter(Mandatory = $true)]
    [object]$CreateContainersJob,
)

Import-Module (Join-Path $ScriptsPath "Modules\Alpaca.psd1") -Scope Global -DisableNameChecking

$project = $env:_project

# Get backend Url from needs context
Write-Host "Get Alpaca backend url from initialization job context"
$backendUrl = $InitializationJob.outputs.backendUrl
Write-Host "Setting ALPACA_BACKEND_URL to '$backendUrl'"
$env:ALPACA_BACKEND_URL = $backendUrl

# Get container information from needs context
Write-Host "Get Alpaca container information from create containers job context"
$containers = @("$($CreateContainersJob.outputs.containersJson)" | ConvertFrom-Json)
$container = $containers | Where-Object { $_.Project -eq $project }
if (! $container) {
    throw "No Alpaca container information for project '$project' found in needs context."
}
Write-Host "Setting ALPACA_CONTAINER_ID to '$($container.Id)'"
$env:ALPACA_CONTAINER_ID = $container.Id

# Initialize container endpoint and authentication context
$password = ConvertTo-SecureString -String $container.Password -AsPlainText
$containerAuthContext = @{"username" = $container.User; "Password" = $password }
$containerEnvironment = $container.Url

Write-Host "Setting bcAuthContext to '$([pscustomobject]$containerAuthContext)'"
Set-Variable -Name 'bcAuthContext' -value $containerAuthContext -scope 1
Write-Host "Setting environment to '$($containerEnvironment)'"
Set-Variable -Name 'environment' -value $containerEnvironment -scope 1

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
if ($runAlPipelineOverrides | Where-Object { $_ -ne "PipelineInitialize"}) {
    Write-Host "Loading Alpaca overrides"
    $runAlPipelineOverrides | ForEach-Object {
        $scriptName = $_
        $scriptPath = Join-Path $ScriptsPath "Overrides\RunAlPipeline\$scriptName.ps1"
        if (Test-Path -Path $scriptPath -Type Leaf) {
            Write-Host "Set Alpaca override for $scriptName"
            $existingScriptBlock = Get-Variable -Name $scriptName -ValueOnly -Scope 1 -ErrorAction Ignore
            if ($existingScriptBlock) {
                Write-Host -ForegroundColor Yellow "Existing $scriptName override"; 
                Write-Host $existingScriptBlock.ToString()
                Set-Variable -Name "AlGo$scriptName" -Value $existingScriptBlock -Scope 1
            }
            $scriptBlock = Get-Command $scriptPath | Select-Object -ExpandProperty ScriptBlock
            Set-Variable -Name $scriptName -Value $scriptBlock -Scope 1
        }
    }
}