#region PublicFunctions
function Trace-AlpacaInformation() {
    param(
        [Parameter(ParameterSetName = 'Message', Mandatory = $true)]
        [String] $Message,
        [Parameter(ParameterSetName = 'ActionName', Mandatory = $true)]
        [String] $ActionName,
        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.Dictionary[[System.String], [System.String]]] $AdditionalData = @{}
    )

    if (-not $Message) {
        $Message = "AL-Go action ran: Alpaca$ActionName"
    }

    AddTelemetryEvent -Message $Message -Severity 'Information' -Data $AdditionalData
}

function Trace-AlpacaException() {
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
        try {
            Invoke-ALGoCommand -ScriptBlock { Add-TelemetryProperty -Hashtable $AdditionalData -Key 'ErrorMessage' -Value $ErrorRecord.Exception.Message }
        }
        catch {
            Write-Host "Failed to add telemetry exception details: $_"
        }
    }

    if (-not $Message) {
        $Message = "AL-Go action failed: Alpaca$ActionName"
    }
    AddTelemetryEvent -Message $Message -Severity 'Error' -Data $AdditionalData
}

function Get-MinimizedSettings {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Settings
    )
    begin {
        function GetNonDefaultSettings {
            param(
                [pscustomobject] $Settings,
                [System.Collections.Specialized.OrderedDictionary] $DefaultSettings
            )

            $excludedSettings = @('conditionalSettings', 'partnerTelemetryConnectionString', '$schema')
            $minimizedSettings = [ordered]@{}

            foreach ($property in $Settings.PSObject.Properties) {
                $key = $property.Name
                if ($key -in $excludedSettings) {
                    continue
                }

                $settingValue = $property.Value
                if (-not $DefaultSettings.Contains($key)) {
                    $minimizedSettings[$key] = $settingValue
                    continue
                }

                $defaultValue = $DefaultSettings[$key]
                if (
                    $settingValue -is [System.Management.Automation.PSCustomObject] -and
                    $defaultValue -is [System.Collections.Specialized.OrderedDictionary]
                ) {
                    $nestedSettings = GetNonDefaultSettings -Settings $settingValue -DefaultSettings $defaultValue
                    if (@($nestedSettings.PSObject.Properties).Count -gt 0) {
                        $minimizedSettings[$key] = $nestedSettings
                    }
                    continue
                }

                if ((ConvertTo-Json -InputObject $settingValue -Depth 99 -Compress) -ne (ConvertTo-Json -InputObject $defaultValue -Depth 99 -Compress)) {
                    $minimizedSettings[$key] = $settingValue
                }
            }

            return [pscustomobject]$minimizedSettings
        }
    }
    process {
        Import-ALGoCommands -Commands 'ReadSettings'
        $readSettingsModule = Get-Module -Name ReadSettings
        if (-not $readSettingsModule) {
            throw "ReadSettings module is not loaded. Please ensure that the ReadSettings module is imported before calling this function."
        }
        $defaultSettings = $readSettingsModule.Invoke({ GetDefaultSettings })
        return GetNonDefaultSettings -Settings $Settings -DefaultSettings $defaultSettings
    }
}
function Get-AlpacaActionVersion {
    param()
    # Attention: This function does only work well inside a cosmo alpaca action.
    process {
        $AlpacaVersion = $ENV:GITHUB_ACTION_REF # ACTION_REF is only filled from a simple ref. if ref contains a folder like staging/* it will be empty.
        if (![String]::IsNullOrEmpty($AlpacaVersion)) {
            return $AlpacaVersion
        }
        if ($ENV:GITHUB_ACTION_PATH -like '*Alpaca-Actions*') {
            # /home/runner/work/_actions/cosmoconsult/Alpaca-Actions/staging/emittelemetry/Actions/UpdateSettingsFiles -> staging/emittelemetry
            $Pattern = '.*{0}Alpaca-Actions{0}(.*)[{0}]Actions[{0}].*' -f [Regex]::Escape([System.IO.Path]::DirectorySeparatorChar)
            $AlpacaVersion = (Select-String -InputObject $ENV:GITHUB_ACTION_PATH -Pattern $Pattern).Matches.Groups[1].Value -replace [Regex]::Escape([string][System.IO.Path]::DirectorySeparatorChar), '/'
        }
        return $AlpacaVersion
    }
}

Export-ModuleMember -Function Trace-AlpacaInformation, Trace-AlpacaException, Get-MinimizedSettings, Get-AlpacaActionVersion
#endregion PublicFunctions

#region PrivateFunctions
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
        Invoke-ALGoCommand -ScriptBlock { Add-TelemetryProperty -Hashtable $Data -Key 'PowerShellVersion' -Value ($PSVersionTable.PSVersion.ToString()) }

        $module = Get-Module BcContainerHelper
        if ($module) {
            $versionNoFile = Join-Path -Path (Split-Path $module.Path -Parent) -ChildPath 'Version.txt'
            Invoke-ALGoCommand -ScriptBlock { Add-TelemetryProperty -Hashtable $Data -Key 'BcContainerHelperVersion' -Value (Get-Content -Path $versionNoFile -Encoding UTF8) }
        }

        Invoke-ALGoCommand -ScriptBlock { Add-TelemetryProperty -Hashtable $Data -Key 'WorkflowName' -Value $ENV:GITHUB_WORKFLOW }
        Invoke-ALGoCommand -ScriptBlock { Add-TelemetryProperty -Hashtable $Data -Key 'RunnerOs' -Value $ENV:RUNNER_OS }
        Invoke-ALGoCommand -ScriptBlock { Add-TelemetryProperty -Hashtable $Data -Key 'RunnerEnvironment' -Value $ENV:RUNNER_ENVIRONMENT }
        Invoke-ALGoCommand -ScriptBlock { Add-TelemetryProperty -Hashtable $Data -Key 'RunId' -Value $ENV:GITHUB_RUN_ID }
        Invoke-ALGoCommand -ScriptBlock { Add-TelemetryProperty -Hashtable $Data -Key 'RunNumber' -Value $ENV:GITHUB_RUN_NUMBER }
        Invoke-ALGoCommand -ScriptBlock { Add-TelemetryProperty -Hashtable $Data -Key 'RunAttempt' -Value $ENV:GITHUB_RUN_ATTEMPT }

        ### Add GitHub Repository information
        Invoke-ALGoCommand -ScriptBlock { Add-TelemetryProperty -Hashtable $Data -Key 'Repository' -Value $ENV:GITHUB_REPOSITORY_ID }
        Invoke-ALGoCommand -ScriptBlock { Add-TelemetryProperty -Hashtable $Data -Key 'RepositoryOwnerID' -Value $ENV:GITHUB_REPOSITORY_OWNER_ID }

        $repoSettings = Invoke-ALGoCommand -ScriptBlock { ReadSettings }

        ### Add telemetry that is only sent to the partner
        Invoke-ALGoCommand -ScriptBlock { Add-TelemetryProperty -Hashtable $Data -Key 'RepositoryOwner' -Value $ENV:GITHUB_REPOSITORY_OWNER }
        Invoke-ALGoCommand -ScriptBlock { Add-TelemetryProperty -Hashtable $Data -Key 'RepositoryName' -Value $ENV:GITHUB_REPOSITORY }
        Invoke-ALGoCommand -ScriptBlock { Add-TelemetryProperty -Hashtable $Data -Key 'RefName' -Value $ENV:GITHUB_REF_NAME }

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