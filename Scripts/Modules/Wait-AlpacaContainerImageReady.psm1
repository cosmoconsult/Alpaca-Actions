function Wait-AlpacaContainerImageReady {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ContainerName,
        [Parameter(Mandatory = $true)]
        [string] $Token
    )
    process {
        Write-AlpacaOutput ("[info]Checking status of service: {0}" -f $ContainerName)

        $SleepSeconds = 60
        $SleepSecondsPending = 10
        $TimeoutInMinutes = 50
        $WaitMessage = "Image is building. Going to sleep for {0} seconds." 
        $ContainerStatusCode  = @("Running", "Healthy")
        $success= $true

        $owner = $env:GITHUB_REPOSITORY_OWNER
        $repository = $env:GITHUB_REPOSITORY
        $repository = $repository.replace($owner, "")
        $repository = $repository.replace("/", "")

        $headers = Get-AlpacaAuthenticationHeaders -Token $Token -Owner $owner -Repository $repository
        $headers.add("Content-Type","application/json")

        $apiUrl = Get-AlpacaEndpointUrlWithParam -Controller "service" -Ressource $ContainerName -RouteSuffix "status" -QueryParams $QueryParams

        Write-AlpacaOutput "Get status from $apiUrl"

        $time = New-TimeSpan -Seconds ($TimeoutInMinutes * 60)
        $stoptime = (Get-Date).Add($time)

        $attemps = 1
        do {
            $serviceResult = Invoke-RestMethod $apiUrl -Method 'Get' -Headers $headers -AllowInsecureRedirect -StatusCodeVariable 'StatusCode'
            if ($statusCode -ne 200) {
                $success = $false
                return 
            }
            $currentStatus = $serviceResult.statusCode
            Write-AlpacaOutput "[info] Response: $serviceResult"
            Write-AlpacaOutput ("[info] Status is: {0}" -f $currentStatus)
            $CurrentSleepSeconds = $SleepSeconds
            if($currentStatus -in @("Unknown", "Pending")) {
                $CurrentSleepSeconds = $SleepSecondsPending
            }
            $CurrentWaitMessage = $WaitMessage
            if (!$serviceResult.imageBuilding){
                $CurrentWaitMessage = 'Waiting for service to start. Going to sleep for {0} seconds.'
            }
            Write-AlpacaOutput ("Attempt {0}: {1}" -f $attemps, $($CurrentWaitMessage -f $CurrentSleepSeconds))
            Write-AlpacaOutput
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
                $success= $false
                Write-AlpacaError "Timeout waiting for image build."
                return
            }
        } until ($currentStatus -in $ContainerStatusCode)
        Write-AlpacaOutput "##[info] Reached desired status: $currentStatus"
        $success= $true
    }

    end {
        if(! $success) {
            throw "Error during image build"
        } else {
            Write-AlpacaOutput "Task Completed."
        }
    }

}
Export-ModuleMember -Function Wait-AlpacaContainerImageReady