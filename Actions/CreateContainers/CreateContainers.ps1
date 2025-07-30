Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $true)]
    [string] $Token,
    [Parameter(HelpMessage = "An array of AL-Go projects in compressed JSON format", Mandatory = $true)]
    [string] $ProjectsJson
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

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
        $containers += New-AlpacaContainer -Project $project -Token $Token
    }
} catch {
    Write-AlpacaError "Failed to create containers:`n$($_.Exception.Message)"
    throw "Failed to create containers"
} finally {
    Write-AlpacaOutput "Created $($containers.Count) of $($projects.Count) containers"

    $containersJson = $containers | ConvertTo-Json -Depth 99 -Compress -AsArray
    Add-Content -encoding UTF8 -Path $env:GITHUB_ENV -Value "ALPACA_CONTAINERS_JSON=$($containersJson)"
    Add-Content -encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "containersJson=$($containersJson)"
}