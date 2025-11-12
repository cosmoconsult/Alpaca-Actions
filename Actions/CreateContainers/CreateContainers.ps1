Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $true)]
    [string] $Token,
    [Parameter(HelpMessage = "An array of AL-Go projects in compressed JSON format", Mandatory = $true)]
    [string] $ProjectsJson
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

Write-Host "Download and Import AL-Go Helpers"
$helperFiles = @{  
    "AL-Go-Helper.ps1"     = "https://raw.githubusercontent.com/microsoft/AL-Go/ab2f5319ed073c542e03914f8ae6c0fda029ee1e/Actions/AL-Go-Helper.ps1"
    "settings.schema.json" = "https://raw.githubusercontent.com/microsoft/AL-Go/ab2f5319ed073c542e03914f8ae6c0fda029ee1e/Actions/settings.schema.json"
}
foreach ($file in $helperFiles.Keys) {
    $url = $helperFiles[$file]
    $dest = Join-Path $PSScriptRoot $file
    try {
        Invoke-RestMethod -Uri $url -Headers @{ "Authorization" = "token $Token" } -OutFile $dest -ErrorAction Stop
    }
    catch {
        throw "Failed to download ${file} from ${url}: " + $_.Exception.Message
    }
}
. (Join-Path $PSScriptRoot "AL-Go-Helper.ps1")

try {
    $projects = [string[]]("$ProjectsJson" | ConvertFrom-Json)
    if (! $projects) {
        throw "No AL-Go projects defined."
    }
    Write-AlpacaOutput "Creating containers for projects: '$($projects -join "', '")' [$($projects.Count)]"
} 
catch {
    throw "Failed to determine AL-Go projects: $($_.Exception.Message)"
}

$containers = @()

try {
    foreach ($project in $projects) {
        Write-AlpacaOutput "Getting Project Settings for project: '$project'"
        $ProjectSettings = ReadSettings -project $project
        if ($ProjectSettings.buildModes.Count -le 0) {
            Write-AlpacaOutput "No build modes defined for project '$project', using default build mode."
            $ProjectSettings.buildModes = @("Default")
        }
        foreach ($BuildMode in $ProjectSettings.buildModes) {
            Write-AlpacaOutput "Creating container for project '$project' with build mode '$BuildMode'"
            $containers += New-AlpacaContainer -Project $project -Token $Token -BuildMode $BuildMode
        }
    }
}
catch {
    Write-AlpacaError "Failed to create containers:`n$($_.Exception.Message)"
    throw "Failed to create containers"
} finally {
    Write-AlpacaOutput "Created $($containers.Count) containers"

    $containersJson = $containers | ConvertTo-Json -Depth 99 -Compress -AsArray
    Add-Content -encoding UTF8 -Path $env:GITHUB_ENV -Value "ALPACA_CONTAINERS_JSON=$($containersJson)"
    Add-Content -encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "containersJson=$($containersJson)"
}