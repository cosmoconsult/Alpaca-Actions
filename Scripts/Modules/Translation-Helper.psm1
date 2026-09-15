 $script:XliffSyncInstalled = $false
 function Install-XliffSync {
    # Install XliffSync module if not already installed
    # save state in global variable to avoid multiple installations and avoid slow Get-InstalledModule calls
    if ($script:XliffSyncInstalled) {
        Write-AlpacaOutput "XliffSync module already installed in this session"
        return
    }
    Install-Module -Name XliffSync -Scope CurrentUser -Force
    $script:XliffSyncInstalled = $true

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

    $globalXlfFiles = @() # Initialize variable to enforce an array due to strict mode
    $globalXlfFiles += Get-ChildItem -Path $Folder -Include '*.g.xlf' -Recurse
    Write-AlpacaOutput "Found $($globalXlfFiles.Count) files in $Folder"

    if (-not $globalXlfFiles) {
        Write-AlpacaError "No .g.xlf files found in $Folder!"
        Write-AlpacaOutput ("Files in directory: {0}" -f ((Get-ChildItem -Path $Folder -Recurse | Select-Object -ExpandProperty FullName -ErrorAction SilentlyContinue | ForEach-Object { $_.Replace($Folder, '').TrimStart('\') } ) -join ', '))
        throw
    }

    Install-XliffSync

    foreach ($globalXlfFile in $globalXlfFiles) {
        $formatTranslationUnit = { param($TranslationUnit) $TranslationUnit.note | Where-Object from -EQ 'Xliff Generator' | Select-Object -ExpandProperty '#text' }

        foreach ($language in $Languages) {
            Sync-XliffTranslations `
                -sourcePath $globalXlfFile.FullName `
                -targetLanguage $language `
                -parseFromDeveloperNote `
                -parseFromDeveloperNoteOverwrite `
                -parseFromDeveloperNoteSeparator "||" `
                -detectSourceTextChanges:$false `
                -AzureDevOps 'warning' `
                -printProblems `
                -FormatTranslationUnit $formatTranslationUnit `
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

    $translatedXlfFiles = @() # Initialize variable to enforce an array due to strict mode
    $translatedXlfFiles += Get-ChildItem -Path $Folder -Include '*.??-??.xlf' -Exclude '*.g.xlf' -Recurse
    Write-AlpacaOutput "Found $($translatedXlfFiles.Count) files in $Folder"

    if ($translatedXlfFiles.Count -eq 0) {
        Write-AlpacaWarning "No translated .xlf files found in $Folder!"
        Write-AlpacaOutput ("Files in directory: {0}" -f ((Get-ChildItem -Path $Folder -Recurse | Select-Object -ExpandProperty FullName -ErrorAction SilentlyContinue | ForEach-Object { $_.Replace($Folder, '').TrimStart('\') } ) -join ', '))
        return
    }

    Install-XliffSync

    $issues = @()
    $formatTranslationUnit = { param($TranslationUnit)
        @(
            $TranslationUnit.note | Where-Object from -eq 'Xliff Generator' | Select-Object -First 1 -ExpandProperty '#text'
            $TranslationUnit.note | Where-Object from -eq 'Xliff Sync' | Select-Object -ExpandProperty '#text'
        ) -join "'`n- Note: '"
    }

    foreach ($translatedXlfFile in $translatedXlfFiles) {
        $issues += Test-XliffTranslations `
            -targetPath $translatedXlfFile.FullName `
            -checkForMissing `
            -checkForProblems:$( $Rules.Count -gt 0 ) `
            -translationRules @( $Rules | Where-Object { $_ -ne 'All' } ) `
            -translationRulesEnableAll:$( $Rules -contains 'All' ) `
            -AzureDevOps 'warning' `
            -printProblems `
            -FormatTranslationUnit $formatTranslationUnit `
            *>&1 | Invoke-AlpacaOutputHandler
    }

    $issueCount = $issues.Count
    if ($issueCount -gt 0) {
        Write-AlpacaError "${issueCount} issues detected in translation files!"
        throw "${issueCount} issues detected in translation files!"
    }
}
Export-ModuleMember -Function Test-TranslationFiles