function Wait-AlpacaContainerImageReady {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ContainerName,
        [Parameter(Mandatory = $true)]
        [string] $Token
    )
    process {
        Write-AlpacaOutput ("[info]Checking status of container: {0}" -f $ContainerName)

        $sleepSeconds = 60
        $sleepSecondsPending = 10
        $timeoutInMinutes = 50
        $waitMessage = "Image is building. Going to sleep for {0} seconds."
        $containerStatusCode = @("Starting", "Running", "Healthy")
        $success = $true

        $owner = $env:GITHUB_REPOSITORY_OWNER
        $repository = $env:GITHUB_REPOSITORY
        $repository = $repository.replace($owner, "")
        $repository = $repository.replace("/", "")

        $headers = Get-AlpacaAuthenticationHeaders -Token $Token
        $headers.add("Content-Type", "application/json")

        $apiUrl = Get-AlpacaEndpointUrlWithParam -Controller "Container" -Endpoint "Container" -Ressource $ContainerName
        Write-AlpacaOutput "Get status of container '$ContainerName' from $apiUrl"

        $time = New-TimeSpan -Seconds ($timeoutInMinutes * 60)
        $stoptime = (Get-Date).Add($time)

        $attemps = 1
        do {
            try {
                $containerResult = Invoke-AlpacaApiRequest -Url $apiUrl -Method 'GET' -Headers $headers -Retries 3
            }
            catch {
                Write-AlpacaError "Error while getting container status: $_"
                $success = $false
                return
            }
            Write-AlpacaOutput "[info] Response: $($containerResult.status | ConvertTo-Json -Compress)"
            $currentStatus = $containerResult.status.state
            Write-AlpacaOutput ("[info] Status is: {0}" -f $currentStatus)
            $currentSleepSeconds = $sleepSeconds
            if ($currentStatus -in @("Unknown", "Pending")) {
                $currentSleepSeconds = $sleepSecondsPending
            }
            if ($currentStatus -notin $containerStatusCode) {
                switch ($currentStatus) {
                    "Error" {
                        $success = $false
                        Write-AlpacaError "An error occurred during building the image."
                        return
                    }
                    default {
                        $currentWaitMessage = $waitMessage
                        if (!$containerResult.status.imageBuilding) {
                            $currentWaitMessage = 'Waiting for container to start. Going to sleep for {0} seconds.'
                        }
                        Write-AlpacaOutput ("Attempt {0}: {1}" -f $attemps, $($currentWaitMessage -f $currentSleepSeconds))
                        Write-AlpacaOutput ""
                        Start-Sleep -Seconds $currentSleepSeconds
                    }
                }
            }
            $attemps += 1
            if ((Get-Date) -gt $stoptime) {
                $success = $false
                Write-AlpacaError "Timeout waiting for image build."
                return
            }
        } until ($currentStatus -in $containerStatusCode)
        Write-AlpacaOutput "##[info] Reached desired status: $currentStatus"
        $success = $true
    }

    end {
        if (! $success) {
            throw "Error during image build"
        }
        else {
            Write-AlpacaOutput "Task Completed."
        }
    }

}
Export-ModuleMember -Function Wait-AlpacaContainerImageReady