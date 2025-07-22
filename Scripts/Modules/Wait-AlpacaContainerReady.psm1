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
                Write-Host "Wait for container connection ($InitialSleepSeconds sec)"
                Start-Sleep -Seconds $InitialSleepSeconds
            }

            $owner = $Env:GITHUB_REPOSITORY_OWNER
            $repository = $Env:GITHUB_REPOSITORY
            $repository = $repository.replace($owner, "")
            $repository = $repository.replace("/", "")

            
            $headers = Get-AlpacaAuthenticationHeaders -Token $Token -Owner $owner -Repository $repository
            $headers.add("accept","application/text")

            $QueryParams = @{
                "api-version" = "0.12"
                tail = 5000
            }
            $apiUrl = Get-AlpacaEndpointUrlWithParam -Controller "task" -Ressource $ContainerName -RouteSuffix "logs"  -QueryParams $QueryParams
                
            while ($waitForContainer) {  

                $result = Invoke-RestMethod $apiUrl -Method 'Get' -Headers $headers -AllowInsecureRedirect -StatusCodeVariable 'StatusCode'

                $content = $result -split "\n"

                if ($StatusCode -ne 200) {
                        
                    if ($tries -lt $MaxTries) {
                        $tries = $tries + 1
                    }
                    else {
                        Write-Host "::error::Error while getting logs from container"
                        Write-Host "::error::Content: $($content)"
                        $waitForContainer = $false
                        $success = $false
                        return
                    }
                }
                    
                # Check for Errors, Warnings, Ready-String
                $indentation = 0
                foreach ($line in ($content | Select-Object -Skip $takenLines -First ($content.Length - 1))) {
                    if (! [string]::IsNullOrWhiteSpace($line)) {
                        Write-Host (" " * $indentation * 2) -NoNewline
                    }
                    
                    if ($errorRegex -and ($line -match $errorRegex)) {
                        Write-Host "::error::$line"
                        $success = $false                                
                        $waitForContainer = $false
                    }
                    elseif ($warnRegex -and ($line -match $warnRegex)) {
                        Write-Host "::warning::$line"
                        $warning = $true
                    }
                    elseif ($readyRegex -and ($line -match $readyRegex)) {
                        Write-Host "$($line)"
                        $waitForContainer = $false
                    }
                    elseif ($groupStartRegex -and ($line -match $groupStartRegex)) {
                        Write-Host "$($line -replace $groupStartRegex, '')"
                        $indentation += 1
                    }
                    elseif ($groupEndRegex -and ($line -match $groupEndRegex)) {
                        Write-Host "$($line -replace $groupEndRegex, '')"
                        $indentation = [Math]::Max($indentation - 1, 0)
                    }
                    elseif (! [string]::IsNullOrWhiteSpace($line)) {
                        #Avoid Empty lines in logfile
                        Write-Host "$($line)"
                    }
                }
                $takenLines = $content.Length - 1

                if ($waitForContainer -and $SleepSeconds) {
                    Start-Sleep -Seconds $SleepSeconds
                }
                elseif ($takenLines -lt $content.Length) {
                    Write-Host "$($content | Select-Object -Last 1)"
                }
            }

        }
        catch {
            Write-Host "::notice::Error while waiting for container to be ready"
            $errorMessage = Get-AlpacaExtendedErrorMessage -errorRecord $_
            $errorMessage -replace "`r" -split "`n" | 
                ForEach-Object { Write-Host "`e[31m$_`e[0m" }
            $success = $false
            return
        }
    }
    
    end {
        if (! $success) {
            throw "Errors found during container start"
        }
        elseif ($warning) {
            Write-Host "::warning::container started with warnings"
        }
        else {
            Write-Host "Container is ready."
        }
    }
}

Export-ModuleMember -Function Wait-AlpacaContainerReady