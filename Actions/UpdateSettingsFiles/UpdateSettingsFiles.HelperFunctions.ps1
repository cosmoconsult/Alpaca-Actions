$script:CommentPropertyName = '$comment'

function Read-ALGoSettingsFile {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Path', Justification = 'Used inside script block')]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    return Invoke-ALGoCommand -ScriptBlock { Get-ContentLF -path $Path }
}

function Write-ALGoSettingsFile {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Path', Justification = 'Used inside script block')]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Settings,

        [Parameter(Mandatory = $true)]
        [string] $Path
    )
    $Settings | Invoke-ALGoCommand -ScriptBlock { Set-JsonContentLF -path $Path -object $_ }
}

function Get-ALGoSettingsKeys {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Settings
    )

    if (-not $Settings) {
        return @()
    }

    return @($Settings.PSObject.Properties | ForEach-Object { $_.Name }) | Select-Object -Unique
}

function Get-ALGoConditionalSettings {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Settings,

        [Parameter(Mandatory = $false)]
        $Repository = $null,

        [Parameter(Mandatory = $false)]
        $IncludeComment = $null,
        [Parameter(Mandatory = $false)]
        $ExcludeComment = $null
    )

    if (-not $Settings.PSObject.Properties["conditionalSettings"]) {
        return @()
    }

    if ($Repository) {
        $Repository = $Repository.Split('/')[-1]
    }

    return @(
        $Settings.conditionalSettings |
        Where-Object { $null -eq $Repository -or -not $_.PSObject.Properties["repositories"] -or ($_.repositories | Where-Object { $Repository -like $_ }) } |
        Where-Object { $null -eq $IncludeComment -or ($_.PSObject.Properties[$script:CommentPropertyName] -and $_.$($script:CommentPropertyName) -like $IncludeComment) } |
        Where-Object { $null -eq $ExcludeComment -or -not $_.PSObject.Properties[$script:CommentPropertyName] -or $_.$($script:CommentPropertyName) -notlike $ExcludeComment } |
        ForEach-Object {
            $copy = $_.PSObject.Copy()
            $copy.PSObject.Properties.Remove($script:CommentPropertyName)
            return $copy
        }
    )
}

function Get-ALGoConditionalSettingsObjects {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Settings,

        [Parameter(Mandatory = $false)]
        $Repository = $null,

        [Parameter(Mandatory = $false)]
        $IncludeComment = $null,
        [Parameter(Mandatory = $false)]
        $ExcludeComment = $null
    )

    return Get-ALGoConditionalSettings @PSBoundParameters |
    ForEach-Object {
        @{
            Entry = $_
            Keys  = @(Get-ALGoSettingsKeys -Settings $_.settings)
            Json  = $_ | ConvertTo-Json -Depth 99 -Compress
        }
    }
}

function Get-ALGoConditionalSettingsKeys {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Settings,

        [Parameter(Mandatory = $false)]
        $Repository = $null,

        [Parameter(Mandatory = $false)]
        $IncludeComment = $null,
        [Parameter(Mandatory = $false)]
        $ExcludeComment = $null
    )

    return Get-ALGoConditionalSettingsObjects @PSBoundParameters | Select-Object -ExpandProperty Keys | Select-Object -Unique
}

function Compare-ALGoConditionalSettingsObjects {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [hashtable[]] $ReferenceObjects,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [hashtable[]] $DifferenceObjects
    )

    if ($ReferenceObjects.Count -ne $DifferenceObjects.Count) {
        return $false
    }

    foreach ($referenceObject in $ReferenceObjects) {
        $matchingDifferenceObject = $DifferenceObjects | Where-Object { $_.Json -eq $referenceObject.Json }
        if (-not $matchingDifferenceObject) {
            return $false
        }
    }

    return $true
}

function Get-ALGoSettingsObject {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Source,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Content,
        [Parameter(Mandatory = $false)]
        [bool] $Immutable = $false,
        [Parameter(Mandatory = $false)]
        [string] $RedirectTo = $null
    )

    $alGoSettingsObject = @{
        Source     = $Source
        Settings   = [pscustomobject]@{}

        Updated    = $false
        Updates    = @()

        Keys       = @()

        Immutable  = $Immutable
        RedirectTo = $RedirectTo
    }

    if ($Content) {
        $settings = $Content | ConvertFrom-Json -ErrorAction Stop
        if ($settings) {
            $alGoSettingsObject.Settings = $settings
            $alGoSettingsObject.Keys = @(Get-ALGoSettingsKeys -Settings $settings)
        }
    }

    return $alGoSettingsObject
}

function Get-ALGoSettingsObjects {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $ALGoOrgSettingsJson,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $ALGoRepoSettingsJson,

        [string] $Path = $env:GITHUB_WORKSPACE
    )
    try {
        Write-AlpacaGroupStart "Get AL-Go Settings Objects from environment variables and settings files"

        Write-AlpacaOutput "Get AL-Go Org Settings"
        $alGoOrgSettingsObject = Get-ALGoSettingsObject -Source "ALGoOrgSettings" -Content $ALGoOrgSettingsJson `
            -Immutable $true

        Write-AlpacaDebug "AL-Go Org settings:`n$($alGoOrgSettingsObject | ConvertTo-Json -Depth 10)"
        $alGoOrgSettingsObject

        Write-AlpacaOutput "Get AL-Go Repo Settings"
        $alGoRepoSettingsObject = Get-ALGoSettingsObject -Source "ALGoRepoSettings" -Content $ALGoRepoSettingsJson `
            -Immutable $true `
            -RedirectTo ".github/AL-Go-Settings.json" # Redirect to the repository settings file in the .github directory

        Write-AlpacaDebug "AL-Go Repo settings:`n$($alGoRepoSettingsObject | ConvertTo-Json -Depth 10)"
        $alGoRepoSettingsObject

        Write-AlpacaGroupStart "Find AL-Go Settings Files"
        $alGoSettingsFilePaths = @(Find-ALGoSettingsFiles -WorkspacePath $Path)
        Write-AlpacaGroupEnd

        Write-AlpacaGroupStart "Read AL-Go Settings Files"
        foreach ($alGoSettingsFilePath in $alGoSettingsFilePaths) {
            if (Test-Path $alGoSettingsFilePath -PathType Leaf) {
                try {
                    Write-AlpacaOutput "Read AL-Go Settings File: $alGoSettingsFilePath"

                    $alGoFileSettingsObjectParams = @{
                        Source  = (Resolve-Path -Path $alGoSettingsFilePath -Relative -RelativeBasePath $Path).Replace('\', '/') # Make source path relative and use forward slashes for consistency
                        Content = Read-ALGoSettingsFile -Path $alGoSettingsFilePath
                    }

                    if ($alGoSettingsFilePath -like "*[\\/].github[\\/]AL-Go-TemplateRepoSettings.doNotEdit.json") {
                        $alGoFileSettingsObjectParams.Immutable = $true
                        $alGoFileSettingsObjectParams.RedirectTo = ".github/AL-Go-Settings.json" # Redirect to the repository settings file in the .github directory
                    }
                    if ($alGoSettingsFilePath -like "*[\\/].github[\\/]AL-Go-TemplateProjectSettings.doNotEdit.json") {
                        $alGoFileSettingsObjectParams.Immutable = $true
                        $alGoFileSettingsObjectParams.RedirectTo = "*.AL-Go/settings.json" # Redirect to the project settings files in the .AL-Go directories of all levels
                    }

                    $alGoFileSettingsObject = Get-ALGoSettingsObject @alGoFileSettingsObjectParams

                    Write-AlpacaDebug "AL-Go File Settings:`n$($alGoFileSettingsObject | ConvertTo-Json -Depth 10)"
                    $alGoFileSettingsObject
                }
                catch {
                    throw "Error reading AL-Go Settings file. Error was $($_.Exception.Message).`n$($_.ScriptStackTrace)"
                }
            }
        }
        Write-AlpacaGroupEnd
    }
    finally {
        Write-AlpacaGroupEnd
    }
}

function Get-ALGoOrgConditionalSettingsObjectsToInherit {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $AlGoSettingsObjects,

        [Parameter(Mandatory = $true)]
        [string] $Repository,

        [Parameter(Mandatory = $false)]
        [switch] $EnforceOrgBuildModesSettings
    )
    try {
        Write-AlpacaGroupStart "Get organization-level conditional settings to inherit"

        $alGoOrgSettingsObject = $AlGoSettingsObjects | Where-Object { $_.Source -eq "ALGoOrgSettings" } | Select-Object -First 1

        $alGoOrgConditionalSettingsObjects = @(
            Get-ALGoConditionalSettingsObjects -Settings $alGoOrgSettingsObject.Settings -Repository $Repository |
            # Filter for entries that have settings with at least one property
            Where-Object { $_.Entry.PSObject.Properties["settings"] -and $_.Entry.settings -and @($_.Entry.settings.PSObject.Properties) }
        )

        if (-not $alGoOrgConditionalSettingsObjects) {
            Write-AlpacaOutput "No organization-level conditional settings found for repository ${Repository}. Nothing to Inherit."
            return @()
        }

        $alGoOrgConditionalSettingsObjectsToInherit = @()

        try {
            Write-AlpacaGroupStart "Determine organization-level build modes conditional settings to inherit for repository ${Repository}"

            if (-not $EnforceOrgBuildModesSettings) {
                Write-AlpacaOutput "Organization build modes settings enforcement is disabled. Skipping."
            }
            elseif (-not ($AlGoSettingsObjects | Where-Object { "buildModes" -in @($_.Keys) + @(Get-ALGoConditionalSettingsKeys -Settings $_.Settings -Repository $Repository -ExcludeComment "*") })) {
                Write-AlpacaOutput "No build modes configured in repository ${Repository}. Skipping."
            }
            else {
                $alGoOrgBuildModesConditionalSettings = @($alGoOrgConditionalSettingsObjects | Where-Object { $_.Entry.PSObject.Properties["buildModes"] -and $_.Entry.buildModes })
                if ($alGoOrgBuildModesConditionalSettings) {
                    Write-AlpacaOutput "Organization-level build modes conditional settings found for repository ${Repository}. Inheriting $($alGoOrgBuildModesConditionalSettings.Count) build mode conditional settings."
                    $alGoOrgConditionalSettingsObjectsToInherit += @($alGoOrgBuildModesConditionalSettings | Where-Object { $alGoOrgConditionalSettingsObjectsToInherit -notcontains $_ })
                }
                else {
                    Write-AlpacaOutput "No organization-level build modes conditional settings found for repository ${Repository}. Nothing to Inherit."
                }
            }
        }
        finally {
            Write-AlpacaGroupEnd
        }

        return $alGoOrgConditionalSettingsObjectsToInherit
    }
    finally {
        Write-AlpacaGroupEnd
    }
}

function Update-ALGoSettingsObjectsWithOrgConditionalSettings {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $AlGoSettingsObjects,

        [Parameter(Mandatory = $true)]
        [string] $Repository,

        [Parameter(Mandatory = $true)]
        [bool] $EnforceOrgBuildModesSettings
    )
    Write-AlpacaGroupStart "Update AL-Go Settings with organization-level conditional settings"

    $comment = 'DO NOT EDIT. Inherited from ALGoOrgSettings'

    $mutableAlGoSettingsObjects = @($AlGoSettingsObjects | Where-Object { -not $_.Immutable })
    $immutableAlGoSettingsObjects = @($AlGoSettingsObjects | Where-Object { $_.Immutable })

    $alGoOrgConditionalSettingsObjectsToInherit = @(Get-ALGoOrgConditionalSettingsObjectsToInherit -AlGoSettingsObjects $AlGoSettingsObjects -Repository $Repository -EnforceOrgBuildModesSettings:$EnforceOrgBuildModesSettings)

    foreach ($alGoSettingsObject in $mutableAlGoSettingsObjects) {
        Write-AlpacaGroupStart "Update AL-Go Settings '$($alGoSettingsObject.Source)'"

        Write-AlpacaDebug "Current AL-Go Settings:`n$($alGoSettingsObject.Settings | ConvertTo-Json -Depth 10)"

        # Get keys from the AL-Go Settings object
        $keys = @($alGoSettingsObject.Keys)
        # Add keys from conditional Settings entries that are not inherited from the organization-level AL-Go Settings (i.e. do not have the inherited comment)
        $keys += @(Get-ALGoConditionalSettingsKeys -Settings $alGoSettingsObject.Settings -Repository $Repository -ExcludeComment $comment)
        # Add keys of immutable AL-Go Settings objects that redirect to this mutable AL-Go Settings object
        $immutableAlGoSettingsObjects |
        Where-Object { $alGoSettingsObject.Source -like $_.RedirectTo } |
        ForEach-Object {
            Write-AlpacaOutput "Include redirection from immutable AL-Go Settings '$($_.Source)'"
            # Add keys from the AL-Go Settings object
            $keys += $_.Keys
            # Add keys from conditional Settings entries that are not inherited from the organization-level AL-Go Settings (i.e. do not have the inherited comment)
            $keys += @(Get-ALGoConditionalSettingsKeys -Settings $_.Settings -Repository $Repository -ExcludeComment $comment)
        }
        $keys = @($keys | Select-Object -Unique)
        Write-AlpacaDebug "Keys: $($keys -join ', ')"

        # Collect existing conditional settings that are inherited from the organization-level AL-Go Settings (i.e. have the inherited comment)
        $oldAlGoOrgConditionalSettingsObjects = @(Get-ALGoConditionalSettingsObjects -Settings $alGoSettingsObject.Settings -IncludeComment $comment)
        Write-AlpacaDebug "Existing inherited conditional settings:`n$($oldAlGoOrgConditionalSettingsObjects | ConvertTo-Json -Depth 10)"
        # Collect new conditional settings to be inherited from the organization-level AL-Go Settings based on the defined settings keys
        $newAlGoOrgConditionalSettingsObjects = @($alGoOrgConditionalSettingsObjectsToInherit | Where-Object { $_.Keys | Where-Object { $keys -contains $_ } })
        Write-AlpacaDebug "New inherited conditional settings to apply:`n$($newAlGoOrgConditionalSettingsObjects | ConvertTo-Json -Depth 10)"

        # Determine if the conditional settings of the AL-Go Settings need to be updated
        if (-not (Compare-ALGoConditionalSettingsObjects -ReferenceObjects $oldAlGoOrgConditionalSettingsObjects -DifferenceObjects $newAlGoOrgConditionalSettingsObjects)) {
            Write-AlpacaOutput "Updating conditional settings"
            # Recreate the conditional settings property of the AL-Go settings with the conditional settings that are not inherited from the organization-level AL-Go Settings (i.e. do not have the inherited comment)
            $alGoSettingsObject.Settings |
            Add-Member -MemberType NoteProperty -Name "conditionalSettings" -Value @(Get-ALGoConditionalSettings -Settings $alGoSettingsObject.Settings -ExcludeComment $comment) -Force
            # Add new conditional settings that are inherited from the organization-level AL-Go Settings
            foreach ($newAlGoOrgConditionalSettingsObject in $newAlGoOrgConditionalSettingsObjects) {
                # Create a new object with the inherited comment property and copy all properties from the new conditional settings object to be inherited from the organization-level AL-Go Settings
                $newAlGoOrgConditionalSettings = [pscustomobject][ordered]@{
                    $script:CommentPropertyName = $comment
                }
                foreach ($prop in $newAlGoOrgConditionalSettingsObject.Entry.PSObject.Properties) {
                    $newAlGoOrgConditionalSettings | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value
                }
                $alGoSettingsObject.Settings.conditionalSettings += $newAlGoOrgConditionalSettings
            }
            $alGoSettingsObject.Updated = $true
            $alGoSettingsObject.Updates += "Updated inherited conditional settings from organization-level AL-Go Settings"
        }
        else {
            Write-AlpacaOutput "No updates of conditional settings needed."
        }

        Write-AlpacaDebug "Updated AL-Go Settings:`n$($alGoSettingsObject.Settings | ConvertTo-Json -Depth 10)"

        Write-AlpacaGroupEnd
    }

    Write-AlpacaGroupEnd
}
