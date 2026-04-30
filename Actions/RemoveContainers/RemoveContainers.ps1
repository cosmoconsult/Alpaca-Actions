param (
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $true)]
    [string] $Token,
    [Parameter(HelpMessage = "Optional filter for project name", Mandatory = $false)]
    [string] $ProjectFilter = "*",
    [Parameter(HelpMessage = "Optional filter for build mode", Mandatory = $false)]
    [string] $BuildModeFilter = "*"
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

try {
    Write-AlpacaGroupStart "Determine containers"
    $GetAlpacaContainerSplat = @{
        Token     = $Token
        Project   = $ProjectFilter
        BuildMode = $BuildModeFilter
    }
    $containers = Get-AlpacaContainer @GetAlpacaContainerSplat

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