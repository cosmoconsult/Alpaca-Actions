param (
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $true)]
    [string] $Token,
    [Parameter(HelpMessage = "An array of Alpaca container informations in compressed JSON format", Mandatory = $true)]
    [string] $ContainersJson,
    [Parameter(HelpMessage = "The AL-Go project identifier", Mandatory = $false)]
    [string] $Project = $null,
    [Parameter(HelpMessage = "The AL-Go build mode", Mandatory = $false)]
    [string] $BuildMode = $null
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

try {
    Write-AlpacaGroupStart "Determine containers"

    $containers = [pscustomobject[]]("$ContainersJson" | ConvertFrom-Json)
    if ($null -ne $Project) {
        Write-AlpacaOutput "Filtering by project '$Project'"
        $containers = [pscustomobject[]]($containers | Where-Object { $_.Project -eq $Project })
    }
    if ($null -ne $BuildMode) {
        Write-AlpacaOutput "Filtering by build mode '$BuildMode'"
        $containers = [pscustomobject[]]($containers | Where-Object { $_.BuildMode -eq $BuildMode })
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