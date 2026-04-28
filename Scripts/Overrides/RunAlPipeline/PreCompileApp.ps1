param(
    [string] $AppType,
    [ref] $CompilationParams
)
Write-AlpacaOutput "Using COSMO Alpaca override"

$Settings = $env:Settings | ConvertFrom-Json

#region DebugInfo
if (Get-AlpacaIsDebugMode) {
    Write-AlpacaGroupStart "DebugInfo" #Level 1
    Write-AlpacaDebug "App Type: $AppType"

    Write-AlpacaGroupStart "Compilation Params:" #Level 2
    "$($CompilationParams.Value | ConvertTo-Json -Depth 2)" -split "`n" | ForEach-Object { Write-AlpacaDebug $_ }
    Write-AlpacaGroupEnd #Level 2

    Write-AlpacaDebug "Settings:"
    Write-AlpacaDebug ("Settings.alpaca.createTranslations = {0}" -f $(try { $Settings.alpaca.createTranslations }catch { '' }))
    Write-AlpacaDebug ("Settings.alpaca.translationLanguages = {0}" -f $(try { $Settings.alpaca.translationLanguages -join ', ' }catch { '' }))
    Write-AlpacaDebug ("Settings.alpaca.testTranslations = {0}" -f $(try { $Settings.alpaca.testTranslations }catch { '' }))
    Write-AlpacaDebug ("Settings.alpaca.testTranslationRules = {0}" -f $(try { $Settings.alpaca.testTranslationRules -join ', ' }catch { '' }))
    Write-AlpacaGroupEnd #Level 1
}
#endregion DebugInfo

#region CheckPreconditions
Write-AlpacaGroupStart "Check Preconditions" #Level 1
try {
    if (!$Settings) {
        Write-AlpacaOutput "No settings found, skipping translation and testing translations."
        return
    }
    if ($Settings.PSObject.Properties.Name -notcontains 'alpaca') {
        Write-AlpacaOutput "No 'alpaca' settings found, skipping translation and testing translations."
        return
    }
    $Translate = $Settings.alpaca.PSObject.Properties.Name -contains 'createTranslations' -and $Settings.alpaca.createTranslations
    $TestTranslation = $Settings.alpaca.PSObject.Properties.Name -contains 'testTranslations' -and $Settings.alpaca.testTranslations

    if (!($Translate -or $TestTranslation)) {
        Write-AlpacaOutput "Neither 'createTranslations' nor 'testTranslations' is enabled in settings, skipping translation and testing translations."
        return
    }

    if ($Translate -and $Settings.alpaca.PSObject.Properties.Name -notcontains 'translationLanguages' -or -not $Settings.alpaca.translationLanguages ) {
        Write-AlpacaError "No translation languages configured in 'translationLanguages' setting!"
        return
    }
    $TestTranslationRules = @()
    if ($TestTranslation -and $Settings.alpaca.PSObject.Properties.Name -contains 'testTranslationRules') {
        $TestTranslationRules = $Settings.alpaca.testTranslationRules
    }

    $TranslationEnabledInAppJson = $AppJson.PSObject.Properties.Name -contains 'features' -and $AppJson.features -contains 'TranslationFile' #AppJson comes from parent script
    Write-AlpacaOutput "Translation enabled in app.json: $TranslationEnabledInAppJson"
    $TranslationEnforcedByPipelineSetting = $CompilationParams.Value.Keys.Contains('features') -and $CompilationParams.Value.features -contains 'TranslationFile' #Set by buildmodes=Translated
    Write-AlpacaOutput "Translation enforced by pipeline setting: $TranslationEnforcedByPipelineSetting"
    if (-not ($TranslationEnabledInAppJson -or $TranslationEnforcedByPipelineSetting)) {
        Write-AlpacaOutput "Translation feature is not enabled in app.json or enforced by pipeline settings. Skipping translation and testing translations."
        return
    }
}
finally {
    Write-AlpacaGroupEnd #Level 1
}
#endregion CheckPreconditions


if ($Translate) {
    Write-AlpacaGroupStart "Translate" #Level 1
    $TranslationsFolder = Join-Path $CompilationParams.Value.appProjectFolder "Translations"

    #region ClearTranslations
    if (Test-Path $TranslationsFolder) {
        Write-AlpacaOutput "Clearing existing translation files in $TranslationsFolder"
        Get-ChildItem $TranslationsFolder -Recurse -File -Filter *.xlf | Where-Object { $_.BaseName.EndsWith('.g') -or $Settings.alpaca.translationLanguages -contains $_.BaseName.split('.')[-1] } | ForEach-Object {
            Write-AlpacaDebug "Removing translation file: $($_.FullName)"
            Remove-Item $_.FullName -Force -Confirm:$false
        }
    }
    #endregion ClearTranslations

    #region PreCompile
    Write-AlpacaGroupStart "Pre-Compile App to generate global translation file" #Level 2
    Write-AlpacaOutput "Minimized parameters to speed up compilation"
    $CompilationParamsCopy = $CompilationParams.Value.Clone()
    $CompilationParamsCopy.OutputTo = { Param($line) Write-Host $line }

    # Disable all cops
    $CompilationParamsCopy.EnableCodeCop = $false
    $CompilationParamsCopy.EnableAppSourceCop = $false
    $CompilationParamsCopy.EnablePerTenantExtensionCop = $false
    $CompilationParamsCopy.EnableUICop = $false
    $CompilationParamsCopy.CustomCodeCops = @()

    # Disable all non-mandatory steps
    $CompilationParamsCopy.UpdateDependencies = $false
    $CompilationParamsCopy.CopyAppToSymbolsFolder = $false
    $CompilationParamsCopy.GenerateReportLayout = 'No'
    $CompilationParamsCopy.Generatecrossreferences = $false

    if ($useCompilerFolder) {
        #useCompilerFolder comes from parent scope
        Invoke-Command -ScriptBlock $CompileAppWithBcCompilerFolder -ArgumentList $CompilationParamsCopy *>&1 | Invoke-AlpacaOutputHandler | Out-Null
    }
    else {
        Invoke-Command -ScriptBlock $CompileAppInBcContainer -ArgumentList $CompilationParamsCopy *>&1 | Invoke-AlpacaOutputHandler | Out-Null
    }
    Write-AlpacaGroupEnd #Level 2
    #endregion PreCompile

    #region Translate
    New-TranslationFiles -Folder $TranslationsFolder -Languages $Settings.alpaca.translationLanguages
    #endregion Translate
    Write-AlpacaGroupEnd #Level 1
}

if ($TestTranslation) {
    #region TestTranslations
    Write-AlpacaGroupStart "Test Translations" #Level 1
    $TranslationsFolder = Join-Path $CompilationParams.Value.appProjectFolder "Translations"

    Test-TranslationFiles -Folder $TranslationsFolder -Rules $TestTranslationRules
    Write-AlpacaGroupEnd #Level 1
    #endregion TestTranslations
}

