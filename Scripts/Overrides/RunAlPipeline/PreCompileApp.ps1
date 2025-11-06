param(
    [string] $appType,
    [ref] $compilationParams
)
Write-AlpacaOutput "Using COSMO Alpaca override"

#region Functions
function New-TranslationFiles() {
    # Create translation files (e.g. .de-DE.xlf) based on existing .g.xlf
    param(
        [Parameter(Mandatory = $true)]
        [string]$Folder,
        
        [ValidateScript({ <# en-US,de-DE,de-AT,... #> $_ -cmatch '^[a-z]{2}-[A-Z]{2}$' })]
        [string[]]$Languages = @()
    )
    Write-Host "##[section]Create Translations ($($Languages -join ','))"

    Install-Module -Name XliffSync -Scope CurrentUser -Force
    Write-AlpacaOutput "Successfully installed XliffSync module"

    Write-AlpacaOutput "Found $($Languages.Count) target languages"

    $globalXlfFiles = @() # Initialize variable to enforce an array due to strict mode
    $globalXlfFiles += Get-ChildItem -path $Folder -Include '*.g.xlf' -Recurse
    if (-not $globalXlfFiles) {
        Write-AlpacaError "No .g.xlf files found in $Folder!"
        Write-AlpacaOutput ("Files in directory: {0}" -f ((Get-ChildItem -path $Folder -Recurse | Select-Object -ExpandProperty FullName -ErrorAction SilentlyContinue | ForEach-Object { $_.Replace($Folder, '').TrimStart('\') } )) -join ', ')
        throw
    }
    Write-AlpacaOutput "Found $($globalXlfFiles.Count) files in $Folder"

    foreach ($globalXlfFile in $globalXlfFiles) {
        $FormatTranslationUnit = { param($TranslationUnit) $TranslationUnit.note | Where-Object from -EQ 'Xliff Generator' | Select-Object -ExpandProperty '#text' }

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
                -FormatTranslationUnit $FormatTranslationUnit
        }
    }
}
function Test-TranslationFiles() {
    # Test translation files
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Folder,

        [ValidateSet("All", "ConsecutiveSpacesConsistent", "ConsecutiveSpacesExist", "OptionMemberCount", "OptionLeadingSpaces", "Placeholders", "PlaceholdersDevNote")]
        [string[]]$Rules = @()
    )
    Write-AlpacaOutput "Testing Translations (Rules: $($Rules -join ','))"

    Install-Module -Name XliffSync -Scope CurrentUser -Force
    Write-AlpacaOutput "Successfully installed XliffSync module"

    $translatedXlfFiles = @() # Initialize variable to enforce an array due to strict mode
    $translatedXlfFiles += Get-ChildItem -path $Folder -Include '*.??-??.xlf' -Exclude '*.g.xlf' -Recurse
    Write-AlpacaOutput "Found $($translatedXlfFiles.Count) files in $Folder"

    $issues = @()
    foreach ($translatedXlfFile in $translatedXlfFiles) {
        $FormatTranslationUnit = { param($TranslationUnit) $TranslationUnit.note | Where-Object from -EQ 'Xliff Generator' | Select-Object -ExpandProperty '#text' }

        $issues += Test-XliffTranslations `
            -targetPath $translatedXlfFile.FullName `
            -checkForMissing `
            -checkForProblems:$( $Rules.Count -gt 0 ) `
            -translationRules @( $Rules | Where-Object { $_ -ne 'All' } ) `
            -translationRulesEnableAll:$( $Rules -contains 'All' ) `
            -AzureDevOps 'warning' `
            -printProblems `
            -FormatTranslationUnit $FormatTranslationUnit
    }

    $issueCount = $issues.Count
    if ($issueCount -gt 0) {
        Write-AlpacaError "${issueCount} issues detected in translation files!"
        throw
    }
}
#endregion Functions

#region DebugInfo
Write-AlpacaGroupStart "DebugInfo" #Level 1
if ($env:RUNNER_DEBUG -eq '1' -or $env:GITHUB_RUN_ATTEMPT -gt 1) {
    Write-AlpacaOutput "App Type: $appType"

    Write-AlpacaGroupStart "Compilation Params:" #Level 2
    "$($compilationParams.Value | ConvertTo-Json -Depth 2)" -split "`n" | ForEach-Object { Write-AlpacaOutput $_ }
    Write-AlpacaGroupEnd #Level 2
}
$Settings = $env:Settings | ConvertFrom-Json
Write-AlpacaOutput "Settings:"
Write-AlpacaOutput ("Settings.alpaca.createTranslations = {0}" -f $(try { $Settings.alpaca.createTranslations }catch {}))
Write-AlpacaOutput ("Settings.alpaca.translationLanguages = {0}" -f $(try { $Settings.alpaca.translationLanguages -join ', ' }catch {}))
Write-AlpacaOutput ("Settings.alpaca.TestTranslations = {0}" -f $(try { $Settings.alpaca.TestTranslations }catch {}))
Write-AlpacaOutput ("Settings.alpaca.testTranslationRules = {0}" -f $(try { $Settings.alpaca.testTranslationRules -join ', ' }catch {}))

Write-AlpacaGroupEnd #Level 1
#endregion DebugInfo

#region CheckPreconditions
Write-AlpacaGroupStart "Check Preconditions" #Level 1
if ($Settings.PSObject.Properties.Name -notcontains 'alpaca') {
    Write-AlpacaOutput "No 'alpaca' settings found, skipping precompilation and translation."
    Write-AlpacaGroupEnd #Level 1, early exit
    return
}
if ($Settings.alpaca.PSObject.Properties.Name -notcontains 'createTranslations' -or -not $Settings.alpaca.createTranslations) {
    Write-AlpacaOutput "Skipping precompilation and translation as 'createTranslations' setting is disabled."
    Write-AlpacaGroupEnd #Level 1, early exit
    return
}
if ($Settings.alpaca.PSObject.Properties.Name -notcontains 'translationLanguages' -or -not $Settings.alpaca.translationLanguages ) {
    Write-AlpacaError "No translation languages configured in 'translationLanguages' setting!"
    Write-AlpacaGroupEnd #Level 1, early exit
    return
}

$AppJson = $appJsonContent | ConvertFrom-Json #appJsonContent comes from parent script
$TranslationEnabledInAppJson = $AppJson.PSObject.Properties.Name -contains 'features' -and $AppJson.features -contains 'TranslationFile'
Write-AlpacaOutput "Translation enabled in app.json: $TranslationEnabledInAppJson"
$TranslationEnforcedByPipelineSetting = $compilationParams.Value.PSObject.Properties.Name -contains 'features' -and $compilationParams.Value.features -contains 'TranslationFile' #Set by buildmodes=Translated
Write-AlpacaOutput "Translation enforced by pipeline setting: $TranslationEnforcedByPipelineSetting"
if (-not ($TranslationEnabledInAppJson -or $TranslationEnforcedByPipelineSetting)) {
    Write-AlpacaOutput "Translation feature is not enabled in app.json or enforced by pipeline settings. Skipping precompilation and translation."
    Write-AlpacaGroupEnd #Level 1, early exit
    return
}
Write-AlpacaGroupEnd #Level 1
#endregion CheckPreconditions

Write-AlpacaGroupStart "Precompile and Translate" #Level 1

#region ClearTranslations
$TranslationFolder = Join-Path $compilationParams.Value.appProjectFolder "Translations"
if (-not (Test-Path $TranslationFolder)) {
    Write-AlpacaWarning "Translation folder $TranslationFolder does not exist."
}
Write-AlpacaOutput "Clearing existing translation files in $TranslationFolder"
Get-ChildItem $TranslationFolder -Recurse -File -Filter *.xlf | Foreach-Object {
    Write-AlpacaOutput "Removing translation file: $($_.FullName)"
    Remove-Item $_.FullName -Force -Confirm:$false
}
#endregion ClearTranslations

#region PreCompile
Write-AlpacaOutput "Minimized parameters to speed up compilation"
$compilationParamsCopy = $compilationParams.Value.Clone()
$compilationParamsCopy.OutputTo = { Param($line) }
$compilationParamsCopy.CopyAppToSymbolsFolder = $false
$compilationParamsCopy.Remove("generatecrossreferences")
$compilationParamsCopy.Remove("EnablePerTenantExtensionCop")
$compilationParamsCopy.Remove("EnableAppSourceCop")
$compilationParamsCopy.updateDependencies = $false
$compilationParamsCopy.Remove("EnableCodeCop")
$compilationParamsCopy.Remove("EnableUICop")

if ($useCompilerFolder) {
    $null = Invoke-Command -ScriptBlock $CompileAppWithBcCompilerFolder -ArgumentList $compilationParamsCopy
}
else {
    $null = Invoke-Command -ScriptBlock $CompileAppInBcContainer -ArgumentList $compilationParamsCopy
}
#endregion PreCompile

#region Translate
New-TranslationFiles -Folder $TranslationFolder -Languages $Settings.alpaca.translationLanguages
if ($Settings.alpaca.PSObject.Properties.Name -contains 'TestTranslations' -and $Settings.alpaca.TestTranslations) {
    Test-TranslationFiles -Folder $TranslationFolder -Rules $Settings.alpaca.testTranslationRules
}
#endregion Translate

Write-AlpacaGroupEnd #Level 1
