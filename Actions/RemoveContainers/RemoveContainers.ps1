param (
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $true)]
    [string] $Token,
    [Parameter(HelpMessage = "An array of Alpaca container informations in compressed JSON format", Mandatory = $true)]
    [string] $ContainersJson
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

try {
    $containers = [pscustomobject[]]("$ContainersJson" | ConvertFrom-Json)
    Write-AlpacaOutput "Deleting containers: '$($containers.Id -join "', '")' [$($containers.Count)]"
} 
catch {
    throw "Failed to determine containers: $($_.Exception.Message)"
}

$failures = 0

foreach ($container in $containers) {
    try {
        Remove-AlpacaContainer -Container $container -Token $Token
    } catch {
        Write-AlpacaError "Failed to delete container '$($container.Id)':`n$($_.Exception.Message)"
        $failures += 1
    }
}

Write-AlpacaOutput "Deleted $($containers.Count - $failures) of $($containers.Count) containers"
if ($failures) {
    throw "Failed to delete $failures containers"
}