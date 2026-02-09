param(
    [string] $AppType,
    [ref] $CompilationParams
)
Write-AlpacaOutput "Using COSMO Alpaca override"

#region DebugInfo
Write-AlpacaGroupStart "DebugInfo" #Level 1
if (Get-AlpacaIsDebugMode) {
    Write-AlpacaDebug "App Type: $AppType"

    Write-AlpacaGroupStart "Compilation Params:" #Level 2
    "$($CompilationParams.Value | ConvertTo-Json -Depth 2)" -split "`n" | ForEach-Object { Write-AlpacaDebug $_ }
    Write-AlpacaGroupEnd #Level 2
}
$Settings = $env:Settings | ConvertFrom-Json
Write-AlpacaDebug "Settings:"
Write-AlpacaDebug ("Settings.alpaca.createTranslations = {0}" -f $(try { $Settings.alpaca.createTranslations }catch { '' }))
Write-AlpacaDebug ("Settings.alpaca.translationLanguages = {0}" -f $(try { $Settings.alpaca.translationLanguages -join ', ' }catch { '' }))
Write-AlpacaDebug ("Settings.alpaca.testTranslations = {0}" -f $(try { $Settings.alpaca.testTranslations }catch { '' }))
Write-AlpacaDebug ("Settings.alpaca.testTranslationRules = {0}" -f $(try { $Settings.alpaca.testTranslationRules -join ', ' }catch { '' }))

Write-AlpacaGroupEnd #Level 1
#endregion DebugInfo

#region CheckPreconditions
Write-AlpacaGroupStart "Check Preconditions" #Level 1
try {
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

    #region ClearTranslations
    $TranslationFolder = Join-Path $CompilationParams.Value.appProjectFolder "Translations"
    Write-AlpacaOutput "Clearing existing translation files in $TranslationFolder"
    Get-ChildItem $TranslationFolder -Recurse -File -Filter *.xlf | Where-Object { $_.BaseName.EndsWith('.g') -or $Settings.alpaca.translationLanguages -contains $_.BaseName.split('.')[-1] } | ForEach-Object {
        Write-AlpacaDebug "Removing translation file: $($_.FullName)"
        Remove-Item $_.FullName -Force -Confirm:$false
    }
    #endregion ClearTranslations

    #region PreCompile
    Write-AlpacaOutput "Minimized parameters to speed up compilation"
    $CompilationParamsCopy = $CompilationParams.Value.Clone()
    $CompilationParamsCopy.OutputTo = { param($Line) }
    $CompilationParamsCopy.CopyAppToSymbolsFolder = $false
    $CompilationParamsCopy.Remove("generatecrossreferences")
    $CompilationParamsCopy.Remove("EnablePerTenantExtensionCop")
    $CompilationParamsCopy.Remove("EnableAppSourceCop")
    $CompilationParamsCopy.updateDependencies = $false
    $CompilationParamsCopy.Remove("EnableCodeCop")
    $CompilationParamsCopy.Remove("EnableUICop")

    if ($useCompilerFolder) {
        #useCompilerFolder comes from parent scope
        $null = Invoke-Command -ScriptBlock $CompileAppWithBcCompilerFolder -ArgumentList $CompilationParamsCopy
    }
    else {
        $null = Invoke-Command -ScriptBlock $CompileAppInBcContainer -ArgumentList $CompilationParamsCopy
    }
    #endregion PreCompile

    #region Translate
    New-TranslationFile -Folder $TranslationFolder -Languages $Settings.alpaca.translationLanguages
    #endregion Translate
    Write-AlpacaGroupEnd #Level 1
}

if ($TestTranslation) {
    #region TestTranslations
    Write-AlpacaGroupStart "Test Translations" #Level 1
    $TranslationFolder = Join-Path $CompilationParams.Value.appProjectFolder "Translations"
    if (-not (Test-Path $TranslationFolder)) {
        Write-AlpacaWarning "Translation folder $TranslationFolder does not exist."
    }
    
    Test-TranslationFile -Folder $TranslationFolder -Rules $TestTranslationRules
    Write-AlpacaGroupEnd #Level 1
    #endregion TestTranslations
}
