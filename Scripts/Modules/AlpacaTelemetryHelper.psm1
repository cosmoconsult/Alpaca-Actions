#region PublicFunctions
function Trace-Information() {
    param(
        [Parameter(ParameterSetName = 'Message', Mandatory = $true)]
        [String] $Message,
        [Parameter(ParameterSetName = 'ActionName', Mandatory = $true)]
        [String] $ActionName,
        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.Dictionary[[System.String], [System.String]]] $AdditionalData = @{}
    )

    if (-not $Message) {
        $Message = "Alpaca AL-Go action ran: $ActionName"
    }

    AddTelemetryEvent -Message $Message -Severity 'Information' -Data $AdditionalData
}

function Trace-Exception() {
    param(
        [Parameter(ParameterSetName = 'Message', Mandatory = $true)]
        [String] $Message,
        [Parameter(ParameterSetName = 'ActionName', Mandatory = $true)]
        [String] $ActionName,
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord = $null,
        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.Dictionary[[System.String], [System.String]]] $AdditionalData = @{}
    )

    if ($ErrorRecord -ne $null) {
        Add-TelemetryProperty -Hashtable $AdditionalData -Key 'ErrorMessage' -Value $ErrorRecord.Exception.Message
    }

    if (-not $Message) {
        $Message = "Alpaca AL-Go action failed: $ActionName"
    }
    AddTelemetryEvent -Message $Message -Severity 'Error' -Data $AdditionalData
}

function Invoke-SettingMinimization {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Settings,
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary] $DefaultSettings
    )
    begin {
        function RemoveSettingKey {
            param(
                [Parameter(Mandatory = $true)]
                [object] $Settings,
                [Parameter(Mandatory = $true)]
                [string] $Key
            )
            $Settings.PSObject.Properties.Remove($Key)
        }
        function TestAreEquivalentSettingValues {
            param(
                [object] $Left,
                [object] $Right
            )

            if ($null -eq $Left -and $null -eq $Right) {
                return $true
            }

            if ($null -eq $Left -or $null -eq $Right) {
                return $false
            }

            if (
                $Left -is [System.Management.Automation.PSCustomObject] -and
                $Right -is [System.Collections.Specialized.OrderedDictionary]
            ) {
                return ((ConvertTo-Json -InputObject $Left -Depth 30 -Compress) -eq (ConvertTo-Json -InputObject $Right -Depth 30 -Compress))
            }

            $leftIsCollection = ($Left -is [System.Collections.IEnumerable]) -and -not ($Left -is [string])
            $rightIsCollection = ($Right -is [System.Collections.IEnumerable]) -and -not ($Right -is [string])

            if ($leftIsCollection -xor $rightIsCollection) {
                return $false
            }

            if ($leftIsCollection -and $rightIsCollection) {
                return ((ConvertTo-Json -InputObject @($Left) -Depth 30 -Compress) -eq (ConvertTo-Json -InputObject @($Right) -Depth 30 -Compress))
            }

            return $Left -eq $Right
        }
    }
    process {
        foreach ($property in @($Settings.PSObject.Properties)) {
            $key = $property.Name
            if (-not $DefaultSettings.Contains($key)) {
                continue
            }

            $settingValue = $property.Value
            $defaultValue = $DefaultSettings[$key]

            if (
                $settingValue -is [System.Management.Automation.PSCustomObject] -and
                $defaultValue -is [System.Collections.Specialized.OrderedDictionary]
            ) {
                [void](Invoke-SettingMinimization -Settings $settingValue -DefaultSettings $defaultValue)
                if ($settingValue.PSObject.Properties.Count -eq 0) {
                    RemoveSettingKey -Settings $Settings -Key $key
                }
                continue
            }

            if (TestAreEquivalentSettingValues -Left $settingValue -Right $defaultValue) {
                RemoveSettingKey -Settings $Settings -Key $key
            }
        }

        $Settings.PSObject.Properties.Remove('conditionalSettings')
        $Settings.PSObject.Properties.Remove('partnerTelemetryConnectionString')
        $Settings.PSObject.Properties.Remove('$schema')
        return $Settings
    }
}

Export-ModuleMember -Function Trace-Information, Trace-Exception, Invoke-SettingMinimization
#endregion PublicFunctions

#region PrivateFunctions
function Add-TelemetryProperty() {
    param(
        [System.Collections.Generic.Dictionary[[System.String], [System.String]]] $Hashtable,
        [String] $Key,
        [String] $Value
    )
    if (-not $Hashtable.ContainsKey($Key) -and ($Value -ne '')) {
        $Hashtable.Add($Key, $Value)
    }
}

function AddTelemetryEvent() {
    param(
        [Parameter(Mandatory = $true)]
        [String] $Message,
        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.Dictionary[[System.String], [System.String]]] $Data = @{},
        [Parameter(Mandatory = $false)]
        [ValidateSet("Information", "Warning", "Error")]
        [String] $Severity = 'Information'
    )

    try {
        # Add powershell version
        Add-TelemetryProperty -Hashtable $Data -Key 'PowerShellVersion' -Value ($PSVersionTable.PSVersion.ToString())

        $module = Get-Module BcContainerHelper
        if ($module) {
            $versionNoFile = Join-Path -Path (Split-Path $module.Path -Parent) -ChildPath 'Version.txt'
            Add-TelemetryProperty -Hashtable $Data -Key 'BcContainerHelperVersion' -Value (Get-Content -Path $versionNoFile -Encoding UTF8)
        }

        Add-TelemetryProperty -Hashtable $Data -Key 'WorkflowName' -Value $ENV:GITHUB_WORKFLOW
        Add-TelemetryProperty -Hashtable $Data -Key 'RunnerOs' -Value $ENV:RUNNER_OS
        Add-TelemetryProperty -Hashtable $Data -Key 'RunnerEnvironment' -Value $ENV:RUNNER_ENVIRONMENT
        Add-TelemetryProperty -Hashtable $Data -Key 'RunId' -Value $ENV:GITHUB_RUN_ID
        Add-TelemetryProperty -Hashtable $Data -Key 'RunNumber' -Value $ENV:GITHUB_RUN_NUMBER
        Add-TelemetryProperty -Hashtable $Data -Key 'RunAttempt' -Value $ENV:GITHUB_RUN_ATTEMPT

        ### Add GitHub Repository information
        Add-TelemetryProperty -Hashtable $Data -Key 'Repository' -Value $ENV:GITHUB_REPOSITORY_ID
        Add-TelemetryProperty -Hashtable $Data -Key 'RepositoryOwnerID' -Value $ENV:GITHUB_REPOSITORY_OWNER_ID

        $repoSettings = Invoke-ALGoCommand -ScriptBlock { ReadSettings }

        ### Add telemetry that is only sent to the partner
        Add-TelemetryProperty -Hashtable $Data -Key 'RepositoryOwner' -Value $ENV:GITHUB_REPOSITORY_OWNER
        Add-TelemetryProperty -Hashtable $Data -Key 'RepositoryName' -Value $ENV:GITHUB_REPOSITORY
        Add-TelemetryProperty -Hashtable $Data -Key 'RefName' -Value $ENV:GITHUB_REF_NAME

        # Add alpaca specific telemetry
        Add-TelemetryProperty -Hashtable $Data -Key 'AlpacaVersion' -Value $(GetAlpacaVersion)

        if ($repoSettings.partnerTelemetryConnectionString -ne '') {
            Write-Host "Enabling partner telemetry..."
            $PartnerTelemetryClient = Get-ApplicationInsightsTelemetryClient -TelemetryConnectionString $repoSettings.partnerTelemetryConnectionString
            Write-AlpacaDebug "Emit Trace Message."
            $PartnerTelemetryClient.TrackTrace($Message, [Microsoft.ApplicationInsights.DataContracts.SeverityLevel]::$Severity, $Data)
            Write-AlpacaDebug "Flushing telemetry events."
            $PartnerTelemetryClient.Flush()
            Write-AlpacaDebug "Telemetry events flushed."
        }
    }
    catch {
        Write-Host "Failed to log telemetry event: $_"
    }
}

function GetAlpacaVersion() {
    $AlpacaVersion = $ENV:GITHUB_ACTION_REF # ACTION_REF is only filled from a simple ref. if ref contains a folder like staging/* it will be empty.
    if (![String]::IsNullOrEmpty($AlpacaVersion)) {
        return $AlpacaVersion
    }
    if ($ENV:GITHUB_ACTION_PATH -like '*Alpaca-Actions*') {
        # /home/runner/work/_actions/cosmoconsult/Alpaca-Actions/staging/emittelemetry/Actions/UpdateSettingsFiles -> staging/emittelemetry
        $Pattern = '.*{0}Alpaca-Actions{0}(.*)[{0}]Actions[{0}].*' -f [Regex]::Escape([System.IO.Path]::DirectorySeparatorChar)
        $AlpacaVersion = (Select-String -InputObject $ENV:GITHUB_ACTION_PATH -Pattern $Pattern).Matches.Groups[1].Value -replace [System.IO.Path]::DirectorySeparatorChar, '/'
    }
    return $AlpacaVersion
}

function Get-ApplicationInsightsTelemetryClient($TelemetryConnectionString) {
    Import-ALGoCommands -Commands 'Add-TelemetryProperty'
    $Module = Get-Module -Name TelemetryHelper
    if (-not $Module) {
        throw "TelemetryHelper module is not loaded. Please ensure that the TelemetryHelper module is imported before calling this function."
    }
    $sb = {
        param($TelemetryConnectionString)
        Get-ApplicationInsightsTelemetryClient -TelemetryConnectionString $TelemetryConnectionString
    }
    $Module.Invoke($sb, $TelemetryConnectionString)
}
#endregion PrivateFunctions