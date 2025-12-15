function Get-AlpacaBackendUrl {
    Param(
        [string] $BackendUrl = $env:ALPACA_BACKEND_URL
    )  
    if ([string]::IsNullOrWhiteSpace($BackendUrl)) {
        $BackendUrl = "https://cosmo-alpaca-enterprise.westeurope.cloudapp.azure.com/"
    }
    elseif ($BackendUrl -notlike "*/") {
        $BackendUrl = $BackendUrl + "/"
    }
    return $BackendUrl
}
Export-ModuleMember -Function Get-AlpacaBackendUrl

function Get-AlpacaEndpointUrlWithParam {
    Param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("k8s", "alpaca")]
        [string] $Api = "k8s",
        [Parameter(Mandatory = $true)]
        [string] $Controller,
        [string] $Endpoint,
        [string] $Ressource,
        [string] $RouteSuffix,
        [Hashtable] $QueryParams
    )
    $url = Get-AlpacaBackendUrl
    switch ($Api) {
        "k8s" { $url = $url + "api/docker/release/" }
        "alpaca" { $url = $url + "api/alpaca/release/" }
    }
    $url = $url + $Controller

    if ($Endpoint) {
        $url = $url + "/" + $Endpoint
    }

    if ($Ressource) {
        $url = $url + "/" + $Ressource
    }

    if ($RouteSuffix) {
        $url = $url + "/" + $RouteSuffix
    }
    
    if ($QueryParams) {
        $url = $url + "?"
        $QueryParams.GetEnumerator() | ForEach-Object {
            $url = $url + $_.Key + "=" + $_.Value + "&"
        }
        $url = $url.TrimEnd("&")
    }
    return $url
}
Export-ModuleMember -Function Get-AlpacaEndpointUrlWithParam

function Get-AlpacaAuthenticationHeaders {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Token,
        [Parameter(Mandatory = $false)]
        [string] $Owner,
        [Parameter(Mandatory = $false)]
        [string] $Repository
    )
    $headers = @{
        Authorization = "Bearer $Token"
    }
    # Owner and Repository are required for k8s but not for alpaca api
    if (-not ([String]::IsNullOrEmpty($Owner))) {
        $headers += @{
            "Authorization-Owner" = $Owner
        }
    }
    if (-not ([String]::IsNullOrEmpty($Repository))) {
        $headers += @{
            "Authorization-Repository" = $Repository
        }
    }
    return $headers
}
Export-ModuleMember -Function Get-AlpacaAuthenticationHeaders

function Invoke-AlpacaApiRequest {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Url,
        [string] $Method = 'Get',
        [Hashtable] $Headers,
        [object] $Body
    )
    
    Write-AlpacaDebug -Message "Invoking Alpaca-Api: $Url ($Method)"
    
    try {
        return Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -Body $Body -AllowInsecureRedirect
    }
    catch {
        Resolve-AlpacaApiError -ErrorRecord $_
    }
}
Export-ModuleMember -Function Invoke-AlpacaApiRequest

function Resolve-AlpacaApiError {
    Param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $problemDetails = @{
        status = $null
        title = $null
        detail = $null
        instance = $null
    }

    if ($ErrorRecord.Exception) {
        $problemDetails.detail = $ErrorRecord.Exception.Message
    }

    if ($ErrorRecord.ErrorDetails) {
        try {
            $errorDetails = $ErrorRecord.ErrorDetails.Message | ConvertFrom-Json
            if ($errorDetails -and $errorDetails.PSObject.Properties) {
                foreach ($key in @($problemDetails.Keys)) {
                    if ($errorDetails.PSObject.Properties.Name -contains $key) {
                        $problemDetails[$key] = $errorDetails.$key
                    }
                }
            }
        }
        catch {}
    }

    $errorMessage = "Alpaca-API request failed"
    if ($problemDetails.detail) {
        $errorMessage += ": $($problemDetails.detail)"
    }

    $errorContext = @($problemDetails.status, $problemDetails.title, $problemDetails.instance) | Where-Object { $_ }
    if ($errorContext) {
        $errorMessage += " ($($errorContext -join " "))"
    }

    $ErrorRecord.ErrorDetails = $errorMessage
    throw $ErrorRecord
}
Export-ModuleMember -Function Resolve-AlpacaApiError

function Get-AlpacaConfigNameForWorkflowName {
    switch ($env:GITHUB_WORKFLOW) {
        "NextMajor" { return "NextMajor" }
        "NextMinor" { return "NextMinor" }
        default { return "current" }
    }
}
Export-ModuleMember -Function Get-AlpacaConfigNameForWorkflowName