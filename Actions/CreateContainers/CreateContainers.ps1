Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $true)]
    [string] $Token,
    [Parameter(HelpMessage = "An array of AL-Go projects in compressed JSON format", Mandatory = $true)]
    [string] $ProjectsJson
)

try {
    $projects = [string[]]("$ProjectsJson" | ConvertFrom-Json)
    if (! $projects) {
        throw "No AL-Go projects defined."
    }
    Write-Host "Creating containers for projects: '$($projects -join "', '")' [$($projects.Count)]"
} 
catch {
    throw "Failed to determine AL-Go projects: $($_.Exception.Message)"
}

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

$containers = @()

try {
    foreach ($project in $projects) {
        $containers += New-AlpacaContainer -project $project -token $Token
    }
} catch {
    Write-Host "::error::Failed to create container: $($_.Exception.Message)"
    exit 1;
} finally {
    Write-Host "Created $($containers.Count) of $($projects.Count) containers"

    $containersJson = $containers | ConvertTo-Json -Depth 99 -Compress -AsArray
    Add-Content -encoding UTF8 -Path $env:GITHUB_ENV -Value "ALPACA_CONTAINERS_JSON=$($containersJson)"
    Add-Content -encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "containersJson=$($containersJson)"
}