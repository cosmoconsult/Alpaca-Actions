param (
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $true)]
    [string] $Token,
    [Parameter(HelpMessage = "An array of Alpaca container informations in compressed JSON format", Mandatory = $true)]
    [string] $ContainersJson,
    [Parameter(HelpMessage = "Optional Alpaca container information to filter containers by in JSON format", Mandatory = $false)]
    [string] $FilterJson
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

try {
    Write-AlpacaGroupStart "Determine containers"
    $GetAlpacaContainerSplat = @{
        Token = $Token
    }

    $filter = "$FilterJson" | ConvertFrom-Json
    if ($filter) {
        if ($filter.Project) {
            $GetAlpacaContainerSplat.alGoProject = $filter.Project
        }
        if ($filter.BuildMode) {
            $GetAlpacaContainerSplat.alGoBuildMode = $filter.BuildMode
        }
    }
    $filter.PSObject.Properties.Name | Where-Object { ![String]::IsNullOrEmpty($_) -and $_ -notin "Project", "BuildMode" } | ForEach-Object { Write-AlpacaWarning "Filtering by '$_' = '$($filter.$_)' is currently not supported and will be ignored" }
    $Containers = Get-AlpacaContainer @GetAlpacaContainerSplat

    Write-AlpacaOutput "Determined $($containers.Count) containers:"
    foreach ($container in $containers) {
        Write-AlpacaOutput "- Id: '$($container.Id)', Project: '$($container.Project)', BuildMode: '$($container.BuildMode)'"
    }
}
catch {
    throw "Failed to determine containers:`n$_"
}
finally {
    Write-AlpacaGroupEnd
}

Write-AlpacaGroupStart "Deleting $($containers.Count) containers"
$failures = 0

foreach ($container in $containers) {
    try {
        Remove-AlpacaContainer -Container $container -Token $Token
    } catch {
        Write-AlpacaError "Failed to delete container '$($container.Id)':`n$_"
        $failures += 1
    }
}

Write-AlpacaOutput "Deleted $($containers.Count - $failures) of $($containers.Count) containers"
Write-AlpacaGroupEnd

if ($failures) {
    throw "Failed to delete $failures containers"
}