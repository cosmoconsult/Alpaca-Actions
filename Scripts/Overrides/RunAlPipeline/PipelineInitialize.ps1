param(
    [Parameter(Mandatory = $true)]
    [string] $ScriptsPath,
    [Parameter(Mandatory = $true)]
    [object] $InitializationJob,
    [Parameter(Mandatory = $true)]
    [object] $CreateContainersJob
)

Import-Module (Join-Path $ScriptsPath "Modules/Alpaca.psd1") -Scope Global -DisableNameChecking

try {
    Write-AlpacaGroupStart "PipelineInitialize"

    # Collect informations

    Write-AlpacaGroupStart "Collect Informations"

    Write-AlpacaOutput "Getting AL-Go project from environmental variable"
    $project = $env:_project

    Write-AlpacaOutput "Getting Alpaca backend url from outputs of initialization job"
    $backendUrl = $InitializationJob.outputs.backendUrl

    Write-AlpacaOutput "Getting Alpaca container information from outputs of create containers job"
    $containers = @("$($CreateContainersJob.outputs.containersJson)" | ConvertFrom-Json)
    $container = $containers | Where-Object { $_.Project -eq $project }
    if (! $container) {
        throw "No Alpaca container information for project '$project' found"
    }

    Write-AlpacaOutput "Getting container authentication context from Alpaca container information"
    $containerAuthContext = @{
        username = $container.User
        Password = ConvertTo-SecureString -String $container.Password -AsPlainText
    }

    Write-AlpacaGroupEnd



    # Update variables

    Write-AlpacaGroupStart "Update Variables"

    Write-AlpacaOutput "Setting environmental 'ALGO_PROJECT' to '$project'"
    $env:ALGO_PROJECT = $project

    Write-AlpacaOutput "Setting environmental 'ALPACA_BACKEND_URL' to '$backendUrl'"
    $env:ALPACA_BACKEND_URL = $backendUrl

    Write-AlpacaOutput "Setting environmental 'ALPACA_CONTAINER_ID' to '$($container.Id)'"
    $env:ALPACA_CONTAINER_ID = $container.Id

    Write-AlpacaOutput "Setting parent 'bcAuthContext' to '$([pscustomobject]$containerAuthContext)'"
    Set-Variable -Name 'bcAuthContext' -value $containerAuthContext -scope 1

    Write-AlpacaOutput "Setting parent 'environment' to '$($container.Url)'"
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

    Write-AlpacaOutput "Loading Alpaca overrides from $(Resolve-Path $overridesPath -Relative)"

    Get-Item -Path $overridesPath | 
        Get-ChildItem -Filter "*.ps1" -Exclude "PipelineInitialize.*" -File | 
        ForEach-Object {
            $scriptPath = $_.FullName
            $scriptName = $_.BaseName

            Write-AlpacaOutput "Loading Alpaca override for '$scriptName' from '$(Resolve-Path $scriptPath -Relative)'"
            $scriptBlock = Get-Command $scriptPath | Select-Object -ExpandProperty ScriptBlock

            Write-AlpacaOutput "Getting existing override for '$scriptName'"
            $existingScriptBlock = Get-Variable -Name $scriptName -ValueOnly -Scope 1 -ErrorAction Ignore
            if ($existingScriptBlock) {
                Write-AlpacaOutput "Existing '$scriptName' override" -Color "Yellow" 
                Write-AlpacaOutput $existingScriptBlock.ToString()

                Write-AlpacaOutput "Setting parent 'AlGo$ScriptName' to existing override"
                Set-Variable -Name "AlGo$scriptName" -Value $existingScriptBlock -Scope 1
            }

            Write-AlpacaOutput "Setting parent '$scriptName' to Alpaca override"
            Set-Variable -Name $scriptName -Value $scriptBlock -Scope 1
        }

    Write-AlpacaGroupEnd
}
finally {
    Write-AlpacaGroupEnd
}