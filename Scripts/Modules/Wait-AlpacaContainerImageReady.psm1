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

        $SleepSeconds = 60
        $SleepSecondsPending = 10
        $TimeoutInMinutes = 50
        $WaitMessage = "Image is building. Going to sleep for {0} seconds." 
        $ContainerStatusCode = @("Running", "Healthy")
        $success = $true

        $owner = $env:GITHUB_REPOSITORY_OWNER
        $repository = $env:GITHUB_REPOSITORY
        $repository = $repository.replace($owner, "")
        $repository = $repository.replace("/", "")

        $headers = Get-AlpacaAuthenticationHeaders -Token $Token -Owner $owner -Repository $repository
        $headers.add("Content-Type", "application/json")

        $apiUrl = Get-AlpacaEndpointUrlWithParam -Api 'alpaca' -Controller "Container" -Endpoint "Container" -Ressource $ContainerName
        Write-AlpacaOutput "Get status of container '$ContainerName' from $apiUrl"

        $time = New-TimeSpan -Seconds ($TimeoutInMinutes * 60)
        $stoptime = (Get-Date).Add($time)

        $attemps = 1
        do {
            $containerResult = Invoke-RestMethod $apiUrl -Method 'GET' -Headers $headers -AllowInsecureRedirect -StatusCodeVariable 'StatusCode'
            if ($StatusCode -ne 200) {
                $success = $false
                return 
            }
            Write-AlpacaOutput "[info] Response: $($containerResult.status | ConvertTo-Json -Compress)"
            $currentStatus = $containerResult.status.state
            Write-AlpacaOutput ("[info] Status is: {0}" -f $currentStatus)
            $CurrentSleepSeconds = $SleepSeconds
            if ($currentStatus -in @("Unknown", "Pending")) {
                $CurrentSleepSeconds = $SleepSecondsPending
            }
            $CurrentWaitMessage = $WaitMessage
            if (!$containerResult.status.imageBuilding) {
                $CurrentWaitMessage = 'Waiting for container to start. Going to sleep for {0} seconds.'
            }
            Write-AlpacaOutput ("Attempt {0}: {1}" -f $attemps, $($CurrentWaitMessage -f $CurrentSleepSeconds))
            Write-AlpacaOutput ""
            if ($currentStatus -notin $ContainerStatusCode) {
                switch ($currentStatus) {
                    "Error" { 
                        $success = $false
                        Write-AlpacaError "An error occured during building the image."
                        return
                    }
                    Default {                    
                        Start-Sleep -Seconds $CurrentSleepSeconds
                    }
                }
            }
            $attemps += 1
            if ((Get-Date) -gt $stoptime) {
                $success = $false
                Write-AlpacaError "Timeout waiting for image build."
                return
            }
        } until ($currentStatus -in $ContainerStatusCode)
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