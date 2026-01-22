param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $true)]
    [string] $Token,
    [Parameter(HelpMessage = "Determined build order, including build dimensions, compressed JSON format", Mandatory = $true)]
    [string] $BuildOrderJson
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

try {
    # BuildOrderJson is sonething like this: [{"projects":["ProjectA","ProjectB"],"buildDimensions":[{"project":"ProjectA","gitHubRunner":"\"ubuntu-latest\"","githubRunnerShell":"pwsh","buildMode":"Default","projectName":"ProjectA"},{"project":"ProjectA","gitHubRunner":"\"ubuntu-latest\"","githubRunnerShell":"pwsh","buildMode":"Clean","projectName":"ProjectA"},{"project":"ProjectB","gitHubRunner":"\"ubuntu-latest\"","githubRunnerShell":"pwsh","buildMode":"Default","projectName":"ProjectB"}],"projectsCount":2}]
    # or with multi level projects like this [{"buildDimensions":[{"project":"ProjectA","gitHubRunner":"\"ubuntu-latest\"","buildMode":"Default","projectName":"ProjectA","githubRunnerShell":"pwsh"},{"project":"ProjectA","gitHubRunner":"\"ubuntu-latest\"","buildMode":"Clean","projectName":"ProjectA","githubRunnerShell":"pwsh"}],"projects":["ProjectA"],"projectsCount":1},{"buildDimensions":[{"project":"ProjectB","gitHubRunner":"\"ubuntu-latest\"","buildMode":"Default","projectName":"ProjectB","githubRunnerShell":"pwsh"}],"projects":["ProjectB"],"projectsCount":1}]
    $BuildOrder = ("$BuildOrderJson" | ConvertFrom-Json)
    if ((-not $BuildOrder.buildDimensions) -or $BuildOrder.buildDimensions.Count -eq 0) {
        throw "No AL-Go build dimensions defined."
    }
    Write-AlpacaOutput "Creating containers for build dimensions: '$((  $BuildOrder.buildDimensions | ForEach-Object{$_.project + " - " + $_.buildMode}) -join "', '")' [$($BuildOrder.buildDimensions.Count)]"
} 
catch {
    throw "Failed to determine AL-Go build dimensions:`n$_"
}

$containers = @()

try {
    foreach ($buildDimension in $BuildOrder.buildDimensions) {
        Write-AlpacaOutput "Creating container for project '$($buildDimension.project)' with build mode '$($buildDimension.buildMode)'"
        $containers += New-AlpacaContainer -Project $buildDimension.project -Token $Token -BuildMode $buildDimension.buildMode
    }
}
catch {
    Write-AlpacaError "Failed to create containers:`n$_"
    throw "Failed to create containers"
}
finally {
    Write-AlpacaOutput "Created $($containers.Count) of $($BuildOrder.buildDimensions.Count) containers"

    $containersJson = $containers | ConvertTo-Json -Depth 99 -Compress -AsArray
    Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "ALPACA_CONTAINERS_JSON=$($containersJson)"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "containersJson=$($containersJson)"
}