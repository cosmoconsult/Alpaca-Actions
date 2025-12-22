function Find-SecretSyncSecretsInObject {
    <#
    .SYNOPSIS
        Recursively searches for secret names in a JSON object.

    .DESCRIPTION
        Searches for secret names in a JSON object by:
        - Matching property keys against patterns (e.g., *SecretName, *Secret)
        - Extracting secret names from values containing ${{SECRETNAME}} pattern
        - Recursively searching nested objects and arrays

    .PARAMETER Object
        The JSON object to search. Typically the result of ConvertFrom-Json.

    .PARAMETER Patterns
        Array of wildcard patterns to match against property names (e.g., "*SecretName", "*Secret").

    .EXAMPLE
        $json = Get-Content "settings.json" | ConvertFrom-Json
        $secrets = Find-SecretSyncSecretsInObject -Object $json -Patterns @("*SecretName", "*Secret")
        Finds all secret names in the JSON object.

    .EXAMPLE
        $secrets = Find-SecretSyncSecretsInObject -Object $settings -Patterns "*Secret"
        Finds all properties ending with "Secret" and extracts their values.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Object,
        
        [Parameter(Mandatory = $true)]
        [string[]] $Patterns
    )
    
    $names = @()
    
    if ($Object -is [PSCustomObject]) {
        $properties = $Object | Get-Member -MemberType NoteProperty
        foreach ($prop in $properties) {
            $propName = $prop.Name
            $propValue = $Object.$propName
            
            # Check if property name matches any pattern
            $matchesPattern = $false
            foreach ($pattern in $Patterns) {
                if ($propName -like $pattern) {
                    $matchesPattern = $true
                    break
                }
            }
            
            if ($matchesPattern -and (-not [string]::IsNullOrWhiteSpace($propValue))) {
                # If the value is a string, add it to the list
                if ($propValue -is [string]) {
                    $names += $propValue
                }
            }
            
            # Recursively search nested objects
            $names += Find-SecretSyncSecretsInObject -Object $propValue -Patterns $Patterns
        }
    }
    elseif ($Object -is [array]) {
        foreach ($item in $Object) {
            $names += Find-SecretSyncSecretsInObject -Object $item -Patterns $Patterns
        }
    }
    elseif ($Object -is [string]) {
        # Check if string contains ${{SECRETNAME}} pattern
        if ($Object -match '\$\{\{([^}]+)\}\}') {
            $secretName = $Matches[1].Trim()
            if (-not [string]::IsNullOrWhiteSpace($secretName)) {
                $names += $secretName
            }
        }
    }
    
    return $names
}

Export-ModuleMember -Function Find-SecretSyncSecretsInObject
