param (
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $true)]
    [string] $Token,
    [Parameter(HelpMessage = "An object of key-value pairs with base64 values representing the secrets to sync, usually from ReadSettings of AL-Go", Mandatory = $true)]
    [string] $SecretsJson
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Scripts\Modules\Alpaca.psd1" -Resolve) -DisableNameChecking

try {
    $secrets = [pscustomobject]("$SecretsJson" | ConvertFrom-Json)
    $secretNames = $secrets | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
    
    # Convert all property values from base64
    foreach ($secretName in $secretNames) {
        $base64Value = $secrets.$secretName
        $decodedBytes = [System.Convert]::FromBase64String($base64Value)
        $secrets.$secretName = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
    }
    
    Write-AlpacaOutput "Syncing secrets: '$(($secretNames) -join "', '")' [$($secretNames.Count)]"
} 
catch {
    throw "Failed to determine secrets: $($_.Exception.Message)"
}

try {
    Sync-AlpacaSecrets -Secrets $secrets -Token $Token
    Write-AlpacaOutput "Synced $($secretNames.Count) secrets"
} catch {
    Write-AlpacaError "Failed to sync $($secretNames.Count) secrets:`n$($_.Exception.Message)"
    throw "Failed to sync $($secretNames.Count) secrets"
}