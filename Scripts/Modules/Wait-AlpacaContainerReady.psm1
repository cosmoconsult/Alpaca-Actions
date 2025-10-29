function Wait-AlpacaContainerReady {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ContainerName,
        [Parameter(Mandatory = $true)]
        [string] $Token,
        [Parameter(Mandatory = $false)]
        [System.Collections.ArrayList] $ReadyString = @("Ready for connections!"),
        [Parameter(Mandatory = $false)]
        [System.Collections.ArrayList] $ErrorString = @("[ERROR]"),
        [Parameter(Mandatory = $false)]
        [System.Collections.ArrayList] $WarningString = @("[WARN]"),
        [Parameter(Mandatory = $false)]
        [System.Collections.ArrayList] $GroupStartString = @("::group::", "##[group]"),
        [Parameter(Mandatory = $false)]
        [System.Collections.ArrayList] $GroupEndString = @("::endgroup::", "##[endgroup]"),
        [Parameter(Mandatory = $false)]
        [bool] $PrintLog = $true,
        [Parameter(Mandatory = $false)]
        [int] $MaxTries = 30,
        [Parameter(Mandatory = $false)]
        [int] $SleepSeconds = 5,
        [Parameter(Mandatory = $false)]
        [int] $InitialSleepSeconds = 15
    )
    process {
        try {
            $success = $true
            $warning = $false
            # Wait for Read-String & Handle Exceptions
            # - Warnings
            # - Errors
            # - Log Messages
            $warnRegex = [string]::Join("|", (@() + $WarningString | ForEach-Object { [System.Text.RegularExpressions.Regex]::Escape($_) }) )
            $errorRegex = [string]::Join("|", (@() + $ErrorString | ForEach-Object { [System.Text.RegularExpressions.Regex]::Escape($_) }) )
            $readyRegex = [string]::Join("|", (@() + $ReadyString | ForEach-Object { [System.Text.RegularExpressions.Regex]::Escape($_) }) )
            $groupStartRegex = [string]::Join("|", (@() + $GroupStartString | ForEach-Object { [System.Text.RegularExpressions.Regex]::Escape($_) }) )
            $groupEndRegex = [string]::Join("|", (@() + $GroupEndString | ForEach-Object { [System.Text.RegularExpressions.Regex]::Escape($_) }) )
            $tries = 0
            $waitForContainer = $true
            $takenLines = 0

            if ($InitialSleepSeconds) {
                Write-AlpacaOutput "Wait for container connection ($InitialSleepSeconds sec)"
                Start-Sleep -Seconds $InitialSleepSeconds
            }

            $owner = $env:GITHUB_REPOSITORY_OWNER
            $repository = $env:GITHUB_REPOSITORY
            $repository = $repository.replace($owner, "")
            $repository = $repository.replace("/", "")

            
            $headers = Get-AlpacaAuthenticationHeaders -Token $Token -Owner $owner -Repository $repository
            $headers.add("accept","application/text")

            $QueryParams = @{
                tailLines     = 5000
            }
            $apiUrl = Get-AlpacaEndpointUrlWithParam -api 'alpaca' -Controller "Container" -Endpoint "Container" -Ressource $ContainerName -RouteSuffix "logs" -QueryParams $QueryParams
                
            while ($waitForContainer) {  

                $result = Invoke-RestMethod $apiUrl -Method 'Get' -Headers $headers -AllowInsecureRedirect -StatusCodeVariable 'StatusCode'

                $content = $result -split "\n"

                if ($StatusCode -ne 200) {
                        
                    if ($tries -lt $MaxTries) {
                        $tries = $tries + 1
                    }
                    else {
                        Write-AlpacaError "Error while getting logs from container`nContent:`n$($content)"
                        $waitForContainer = $false
                        $success = $false
                        return
                    }
                }
                    
                # Check for Errors, Warnings, Ready-String
                foreach ($line in ($content | Select-Object -Skip $takenLines -First ($content.Length - 1))) {                    
                    if ($errorRegex -and ($line -match $errorRegex)) {
                        Write-AlpacaError $line
                        $success = $false                                
                        $waitForContainer = $false
                    }
                    elseif ($warnRegex -and ($line -match $warnRegex)) {
                        Write-AlpacaWarning $line
                        $warning = $true
                    }
                    elseif ($readyRegex -and ($line -match $readyRegex)) {
                        Write-AlpacaOutput "$($line)"
                        $waitForContainer = $false
                    }
                    elseif ($groupStartRegex -and ($line -match $groupStartRegex)) {
                        Write-AlpacaGroupStart "$($line -replace $groupStartRegex, '')"
                    }
                    elseif ($groupEndRegex -and ($line -match $groupEndRegex)) {
                        Write-AlpacaGroupEnd "$($line -replace $groupEndRegex, '')"
                    }
                    elseif (! [string]::IsNullOrWhiteSpace($line)) {
                        #Avoid Empty lines in logfile
                        Write-AlpacaOutput "$($line)"
                    }
                }
                $takenLines = $content.Length - 1

                if ($waitForContainer -and $SleepSeconds) {
                    Start-Sleep -Seconds $SleepSeconds
                }
                elseif ($takenLines -lt $content.Length) {
                    Write-AlpacaOutput "$($content | Select-Object -Last 1)"
                }
            }

        }
        catch {
            $errorMessage = Get-AlpacaExtendedErrorMessage -errorRecord $_
            $errorMessage = "Error while waiting for container '$ContainerName' to be ready`n$errorMessage"
            Write-AlpacaError $errorMessage
            $success = $false
            return
        }
    }
    
    end {
        if (! $success) {
            throw "Errors found during container start"
        }
        elseif ($warning) {
            Write-AlpacaWarning "Container started with warnings"
        }
        else {
            Write-AlpacaOutput "Container is ready."
        }
    }
}

Export-ModuleMember -Function Wait-AlpacaContainerReady