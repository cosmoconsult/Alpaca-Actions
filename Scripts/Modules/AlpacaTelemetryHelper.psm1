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

Export-ModuleMember -Function Trace-Information, Trace-Exception
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
        $AlpacaVersion = $ENV:GITHUB_ACTION_REF # ACTION_REF is only filled from a simple ref. if ref contains a folder like staging/* it will be empty.
        if ($AlpacaVersion -eq '' -and $ENV:GITHUB_ACTION_PATH -like '*Alpaca-Actions*') {
            Write-AlpacaDebug "GITHUB_ACTION_REF is empty, trying to get version from GITHUB_ACTION_PATH: $($ENV:GITHUB_ACTION_PATH)"
            $AlpacaVersion = ($ENV:GITHUB_ACTION_PATH -split [System.IO.Path]::DirectorySeparatorChar)[-2]
        }

        Add-TelemetryProperty -Hashtable $Data -Key 'AlpacaVersion' -Value $AlpacaVersion

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
    Import-ALGoCommands -Commands 'Get-ApplicationInsightsTelemetryClient'
    $Module = Get-Module -Name TelemetryHelper
    if (-not $Module) {
        throw "TelemetryHelper module is not loaded. Please ensure that the TelemetryHelper module is imported before calling this function."
    }
    $sb = {
        param($TelemetryConnectionString)
        Write-AlpacaDebug "Creating Application Insights Telemetry Client with connection string: $TelemetryConnectionString"
        Get-ApplicationInsightsTelemetryClient -TelemetryConnectionString $TelemetryConnectionString
    }
    $Module.Invoke($sb, $TelemetryConnectionString)
}
#endregion PrivateFunctions
