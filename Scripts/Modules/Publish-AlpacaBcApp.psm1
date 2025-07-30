
function Publish-AlpacaBcApp {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $ContainerUrl,
        [Parameter(Mandatory = $true)]
        [string] $ContainerUser,
        [Parameter(Mandatory = $true)]
        [string] $ContainerPassword,
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Development','Clean','ForceSync')]
        [string] $SyncMode='Development',
        [Parameter(Mandatory = $false)]
        [string] $Tenant='default') 

    $tries = 0
    $maxtries = 5
    $appName = [System.IO.Path]::GetFileName($Path)
    $success = $false

    Write-AlpacaGroupStart "Publish app $appName"
    
    while (!$success -and $tries -lt $maxTries)
    {
        if ($tries -gt 0) {
            Write-AlpacaGroupStart "Publish attempt $($tries + 1) / $maxtries"
        }

        $handler = New-Object System.Net.Http.HttpClientHandler
        $HttpClient = [System.Net.Http.HttpClient]::new($handler)
        $pair = "$($ContainerUser):$ContainerPassword"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
        $base64 = [System.Convert]::ToBase64String($bytes)
        $HttpClient.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Basic", $base64)
        $HttpClient.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
        $HttpClient.DefaultRequestHeaders.ExpectContinue = $false
        $schemaUpdateMode = "synchronize"
        if ($SyncMode -eq "Clean") {
            $schemaUpdateMode = "recreate";
        } elseif ($SyncMode -eq "ForceSync") {
            $schemaUpdateMode = "forcesync"
        }
        $devServerUrl = $ContainerUrl + "dev/dev/apps?SchemaUpdateMode=$schemaUpdateMode&tenant=$Tenant"
    
        $multipartContent = [System.Net.Http.MultipartFormDataContent]::new()
        $FileStream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open)
        try {
            $fileHeader = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new("form-data")
            $fileHeader.Name = "$appName"
            $fileHeader.FileName = "$appName"
            $fileHeader.FileNameStar = "$appName"
            $fileContent = [System.Net.Http.StreamContent]::new($FileStream)
            $fileContent.Headers.ContentDisposition = $fileHeader
            $multipartContent.Add($fileContent)
            Write-AlpacaOutput "Publishing $appName to $devServerUrl"
            $result = $HttpClient.PostAsync($devServerUrl, $multipartContent).GetAwaiter().GetResult()
            $status = $result.StatusCode
            Write-AlpacaOutput "Returned $status from $devServerUrl"
            if (!$result.IsSuccessStatusCode) {
                $message = "Status Code $($result.StatusCode) : $($result.ReasonPhrase)"
                try {
                    $resultMsg = $result.Content.ReadAsStringAsync().Result
                    try {
                        $json = $resultMsg | ConvertFrom-Json
                        $message += "`n$($json.Message)"
                    }
                    catch {
                        $message += "`n$resultMsg"
                    }
                }
                catch {}
                throw $message
            }
            $success = $true
        }
        catch {
            $errorMessage = Get-AlpacaExtendedErrorMessage -errorRecord $_
            $errorMessage = "Error Publishing App '$appName'`n$errorMessage"

            $tries = $tries + 1
            if ($tries -ge $maxTries) {
                Write-AlpacaError $errorMessage
                throw "Error Publishing App '$appName'"
            }
            else {
                Write-AlpacaError $errorMessage -WithoutGitHubAnnotation
                Write-AlpacaOutput "Failed to publish app, retry after 15 sec"
                Start-Sleep 15
            }
        }
        finally {
            $FileStream.Close()

            Write-AlpacaGroupEnd
        }
    }
}

Export-ModuleMember -Function Publish-AlpacaBcApp