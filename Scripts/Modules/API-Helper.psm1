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
        [Parameter(Mandatory = $true)]
        [string] $Controller,
        [string] $Endpoint,
        [string] $Ressource,
        [string] $RouteSuffix,
        [Hashtable] $QueryParams
    )
    $url = (Get-AlpacaBackendUrl) + "api/alpaca/release"

    $Controller, $Endpoint, $Ressource, $RouteSuffix |
        Where-Object { $_ } |
        ForEach-Object { $_ -split "/" } |
        ForEach-Object { $url = $url + "/" + [System.Uri]::EscapeDataString($_) }

    if ($QueryParams) {
        $url = $url + "?"
        $QueryParams.GetEnumerator() | ForEach-Object {
            $encodedKey = [System.Uri]::EscapeDataString($_.Key)
            $encodedValue = [System.Uri]::EscapeDataString($_.Value)
            $url = $url + $encodedKey + "=" + $encodedValue + "&"
        }
        $url = $url.TrimEnd("&")
    }
    return $url
}
Export-ModuleMember -Function Get-AlpacaEndpointUrlWithParam

function Get-AlpacaAuthenticationHeaders {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Token
    )
    $headers = @{
        Authorization = "Bearer $Token"
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
        [object] $Body,
        [int] $Retries = 0,
        [System.Net.HttpStatusCode[]] $NoRetryStatusCodes = @()
    )

    $NoRetryStatusCodes +=
        [System.Net.HttpStatusCode]::BadRequest,           # 400
        [System.Net.HttpStatusCode]::Unauthorized,         # 401
        [System.Net.HttpStatusCode]::Forbidden,            # 403
        [System.Net.HttpStatusCode]::MethodNotAllowed,     # 405
        [System.Net.HttpStatusCode]::Conflict,             # 409
        [System.Net.HttpStatusCode]::UnprocessableEntity,  # 422
        [System.Net.HttpStatusCode]::NotImplemented        # 501

    $maxAttempts = $Retries + 1
    foreach ($attempt in 1..$maxAttempts) {
        Write-AlpacaDebug -Message "Invoking Alpaca-Api: $Url ($Method) - Attempt $attempt of $maxAttempts"
        try {
            return Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -Body $Body -AllowInsecureRedirect
        }
        catch {
            if ($attempt -lt $maxAttempts) {
                if ($_.Exception -is [System.Net.Http.HttpRequestException] -and $_.Exception.StatusCode -in $NoRetryStatusCodes) {
                    Write-AlpacaDebug -Message "Not retrying for Http status code $([int]$_.Exception.StatusCode)"
                }
                else {
                    Write-AlpacaDebug -Message (Get-AlpacaApiErrorMessage -ErrorRecord $_)
                    $waitSeconds = [Math]::Pow(2, $attempt - 1)
                    Write-AlpacaDebug -Message "Retrying in $waitSeconds second(s)..."
                    Start-Sleep -Seconds $waitSeconds
                    continue
                }
            }

            Resolve-AlpacaApiError -ErrorRecord $_
        }
    }
}
Export-ModuleMember -Function Invoke-AlpacaApiRequest

function Get-AlpacaApiErrorMessage {
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
        catch { Write-Debug "ErrorDetails not parseable as JSON: $($_.Exception.Message)" }
    }

    $errorMessage = "Alpaca-API request failed"

    $errorContext = @($problemDetails.status, $problemDetails.title, $problemDetails.instance) | Where-Object { $_ }
    if ($errorContext) {
        $errorMessage += " ($($errorContext -join " "))"
    }

    if ($problemDetails.detail) {
        $errorMessage += "`n$($problemDetails.detail)"
    }

    return $errorMessage
}
Export-ModuleMember -Function Get-AlpacaApiErrorMessage

function Resolve-AlpacaApiError {
    Param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $errorMessage = Get-AlpacaApiErrorMessage -ErrorRecord $ErrorRecord

    $updatedErrorRecord  = [System.Management.Automation.ErrorRecord]::new($ErrorRecord, $ErrorRecord.Exception)
    $updatedErrorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($errorMessage)
    throw $updatedErrorRecord
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