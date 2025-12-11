param (
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $true)]
    [string] $Token,
    [Parameter(HelpMessage = "An array of Alpaca container informations in compressed JSON format", Mandatory = $true)]
    [string] $ContainersJson,
    [Parameter(HelpMessage = "Optional Alpaca container information to filter containers by in compressed JSON format", Mandatory = $false)]
    [string] $FilterJson
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

try {
    Write-AlpacaGroupStart "Determine containers"

    $containers = [pscustomobject[]]("$ContainersJson" | ConvertFrom-Json)

    $filter = "$FilterJson" | ConvertFrom-Json
    if ($filter) {
        foreach ($key in $filter.PSObject.Properties.Name) {
            $value = $filter.$key
            Write-AlpacaOutput "Filtering by '$key' = '$value'"
            $containers = [pscustomobject[]]($containers | Where-Object { $_.$key -eq $value })
        }
    }
    Write-AlpacaOutput "Determined $($containers.Count) containers:"
    foreach ($container in $containers) {
        Write-AlpacaOutput "- Id: '$($container.Id)', Project: '$($container.Project)', BuildMode: '$($container.BuildMode)'"
    }

    Write-AlpacaGroupEnd
} 
catch {
    throw "Failed to determine containers: $($_.Exception.Message)"
}

Write-AlpacaGroupStart "Deleting containers"
$failures = 0

foreach ($container in $containers) {
    try {
        Remove-AlpacaContainer -Container $container -Token $Token
    } catch {
        Write-AlpacaError "Failed to delete container '$($container.Id)':`n$($_.Exception.Message)" -WithoutGitHubAnnotation
        $failures += 1
    }
}

Write-AlpacaOutput "Deleted $($containers.Count - $failures) of $($containers.Count) containers"
if ($failures) {
    throw "Failed to delete $failures containers"
}

Write-AlpacaGroupEnd