 $script:xliffSyncInstalled = $false
 function Install-XliffSync {
    # Install XliffSync module if not already installed
    # save state in global variable to avoid multiple installations and avoid slow Get-InstalledModule calls
    if ($script:xliffSyncInstalled) {
        Write-AlpacaOutput "XliffSync module already installed in this session"
        return
    }
    Install-Module -Name XliffSync -Scope CurrentUser -Force
    $script:xliffSyncInstalled = $true

    Write-AlpacaOutput "Successfully installed XliffSync module"
}

function New-TranslationFiles() {
    # Create translation files (e.g. .de-DE.xlf) based on existing .g.xlf
    param(
        [Parameter(Mandatory = $true)]
        [string]$Folder,
        [ValidateScript({ <# en-US,de-DE,de-AT,... #> $_ -cmatch '^[a-z]{2}-[A-Z]{2}$' })]
        [string[]]$Languages = @()
    )
    Write-AlpacaOutput "Create Translations ($($Languages -join ','))"

    Write-AlpacaOutput "Found $($Languages.Count) target languages"

    if ($Languages.Count -eq 0) {
        return
    }

    if (! (Test-Path $Folder)) {
        Write-AlpacaError "Folder $Folder does not exist!"
        throw
    }

    $GlobalXlfFiles = @() # Initialize variable to enforce an array due to strict mode
    $GlobalXlfFiles += Get-ChildItem -Path $Folder -Include '*.g.xlf' -Recurse
    Write-AlpacaOutput "Found $($GlobalXlfFiles.Count) files in $Folder"

    if (-not $GlobalXlfFiles) {
        Write-AlpacaError "No .g.xlf files found in $Folder!"
        Write-AlpacaOutput ("Files in directory: {0}" -f ((Get-ChildItem -Path $Folder -Recurse | Select-Object -ExpandProperty FullName -ErrorAction SilentlyContinue | ForEach-Object { $_.Replace($Folder, '').TrimStart('\') } ) -join ', '))
        throw
    }

    Install-XliffSync

    foreach ($GlobalXlfFile in $GlobalXlfFiles) {
        $FormatTranslationUnit = { param($TranslationUnit) $TranslationUnit.note | Where-Object from -EQ 'Xliff Generator' | Select-Object -ExpandProperty '#text' }

        foreach ($Language in $Languages) {
            Sync-XliffTranslations `
                -sourcePath $GlobalXlfFile.FullName `
                -targetLanguage $Language `
                -parseFromDeveloperNote `
                -parseFromDeveloperNoteOverwrite `
                -parseFromDeveloperNoteSeparator "||" `
                -detectSourceTextChanges:$false `
                -AzureDevOps 'warning' `
                -printProblems `
                -FormatTranslationUnit $FormatTranslationUnit `
                *>&1 | Invoke-AlpacaOutputHandler
        }
    }
}
Export-ModuleMember -Function New-TranslationFiles

function Test-TranslationFiles() {
    # Test translation files
    param(
        [Parameter(Mandatory = $true)]
        [string]$Folder,

        [ValidateSet("All", "ConsecutiveSpacesConsistent", "ConsecutiveSpacesExist", "OptionMemberCount", "OptionLeadingSpaces", "Placeholders", "PlaceholdersDevNote")]
        [string[]]$Rules = @()
    )
    Write-AlpacaOutput "Testing Translations (Rules: $($Rules -join ','))"

    if (! (Test-Path $Folder)) {
        Write-AlpacaWarning "Folder $Folder does not exist!"
        return
    }

    $TranslatedXlfFiles = @() # Initialize variable to enforce an array due to strict mode
    $TranslatedXlfFiles += Get-ChildItem -Path $Folder -Include '*.??-??.xlf' -Exclude '*.g.xlf' -Recurse
    Write-AlpacaOutput "Found $($TranslatedXlfFiles.Count) files in $Folder"

    if ($TranslatedXlfFiles.Count -eq 0) {
        Write-AlpacaWarning "No translated .xlf files found in $Folder!"
        Write-AlpacaOutput ("Files in directory: {0}" -f ((Get-ChildItem -Path $Folder -Recurse | Select-Object -ExpandProperty FullName -ErrorAction SilentlyContinue | ForEach-Object { $_.Replace($Folder, '').TrimStart('\') } ) -join ', '))
        return
    }

    Install-XliffSync

    $Issues = @()
    $FormatTranslationUnit = { param($TranslationUnit) $TranslationUnit.note | Where-Object from -EQ 'Xliff Generator' | Select-Object -ExpandProperty '#text' }

    foreach ($TranslatedXlfFile in $TranslatedXlfFiles) {
        $Issues += Test-XliffTranslations `
            -targetPath $TranslatedXlfFile.FullName `
            -checkForMissing `
            -checkForProblems:$( $Rules.Count -gt 0 ) `
            -translationRules @( $Rules | Where-Object { $_ -ne 'All' } ) `
            -translationRulesEnableAll:$( $Rules -contains 'All' ) `
            -AzureDevOps 'warning' `
            -printProblems `
            -FormatTranslationUnit $FormatTranslationUnit `
            *>&1 | Invoke-AlpacaOutputHandler
    }

    $IssueCount = $Issues.Count
    if ($IssueCount -gt 0) {
        Write-AlpacaError "${IssueCount} issues detected in translation files!"
        throw "${IssueCount} issues detected in translation files!"
    }
}
Export-ModuleMember -Function Test-TranslationFiles