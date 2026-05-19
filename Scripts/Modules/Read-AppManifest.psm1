function Read-AppManifest {
    [CmdletBinding()]
    param (
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        Write-AlpacaWarning "App manifest file '$Path' not found."
        return
    }

    $appJson = Get-Content -Path $Path -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (-not $appJson) {
        throw "App manifest '$Path' is not a valid JSON file."
    }

    return $appJson
}
Export-ModuleMember -Function Read-AppManifest