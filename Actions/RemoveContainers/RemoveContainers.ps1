param (
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $true)]
    [string] $Token,
    [Parameter(HelpMessage = "An array of Alpaca container informations in compressed JSON format", Mandatory = $true)]
    [string] $ContainersJson
)

try {
    $containers = [pscustomobject[]]("$ContainersJson" | ConvertFrom-Json)
    Write-Host "Deleting containers: '$($containers.Id -join "', '")' [$($containers.Count)]"
} 
catch {
    throw "Failed to determine containers: $($_.Exception.Message)"
}

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

$failures = 0

foreach ($container in $containers) {
    try {
        Remove-AlpacaContainer -Container $container -Token $Token
    } catch {
        Write-Host "::error::Failed to delete container '$($container.Id)': $($_.Exception.Message)"
        $failures += 1
    }
}

Write-Host "Deleted $($containers.Count - $failures) of $($containers.Count) containers"
if ($failures) {
    exit 1
}