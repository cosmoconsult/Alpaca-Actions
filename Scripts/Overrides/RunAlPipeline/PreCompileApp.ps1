param(
    [string] $AppType,
    [ref] $CompilationParams
)
Write-AlpacaOutput "Using COSMO Alpaca override"

#region DebugInfo
Write-AlpacaGroupStart "DebugInfo" #Level 1
if ($env:RUNNER_DEBUG -eq '1' -or $env:GITHUB_RUN_ATTEMPT -gt 1) {
    Write-AlpacaOutput "App Type: $AppType"

    Write-AlpacaGroupStart "Compilation Params:" #Level 2
    try {
        "$($CompilationParams.Value | ConvertTo-Json -Depth 2)" -split "`n" | ForEach-Object { Write-AlpacaOutput $_ }
    }
    finally {
        Write-AlpacaGroupEnd #Level 2
    }
}
$Settings = $env:Settings | ConvertFrom-Json
Write-AlpacaOutput "Settings:"
Write-AlpacaOutput ("Settings.alpaca.createTranslations = {0}" -f $(try { $Settings.alpaca.createTranslations }catch { '' }))
Write-AlpacaOutput ("Settings.alpaca.translationLanguages = {0}" -f $(try { $Settings.alpaca.translationLanguages -join ', ' }catch { '' }))
Write-AlpacaOutput ("Settings.alpaca.TestTranslations = {0}" -f $(try { $Settings.alpaca.TestTranslations }catch { '' }))
Write-AlpacaOutput ("Settings.alpaca.testTranslationRules = {0}" -f $(try { $Settings.alpaca.testTranslationRules -join ', ' }catch { '' }))

Write-AlpacaGroupEnd #Level 1
#endregion DebugInfo

#region CheckPreconditions
Write-AlpacaGroupStart "Check Preconditions" #Level 1
try {
    if ($Settings.PSObject.Properties.Name -notcontains 'alpaca') {
        Write-AlpacaOutput "No 'alpaca' settings found, skipping precompilation and translation."
        return
    }
    if ($Settings.alpaca.PSObject.Properties.Name -notcontains 'createTranslations' -or -not $Settings.alpaca.createTranslations) {
        Write-AlpacaOutput "Skipping precompilation and translation as 'createTranslations' setting is disabled."
        return
    }
    if ($Settings.alpaca.PSObject.Properties.Name -notcontains 'translationLanguages' -or -not $Settings.alpaca.translationLanguages ) {
        Write-AlpacaError "No translation languages configured in 'translationLanguages' setting!"
        return
    }

    $AppJson = $AppJsonContent | ConvertFrom-Json #appJsonContent comes from parent script
    $TranslationEnabledInAppJson = $AppJson.PSObject.Properties.Name -contains 'features' -and $AppJson.features -contains 'TranslationFile'
    Write-AlpacaOutput "Translation enabled in app.json: $TranslationEnabledInAppJson"
    $TranslationEnforcedByPipelineSetting = $CompilationParams.Value.PSObject.Properties.Name -contains 'features' -and $CompilationParams.Value.features -contains 'TranslationFile' #Set by buildmodes=Translated
    Write-AlpacaOutput "Translation enforced by pipeline setting: $TranslationEnforcedByPipelineSetting"
    if (-not ($TranslationEnabledInAppJson -or $TranslationEnforcedByPipelineSetting)) {
        Write-AlpacaOutput "Translation feature is not enabled in app.json or enforced by pipeline settings. Skipping precompilation and translation."
        return
    }
}
finally {
    Write-AlpacaGroupEnd #Level 1
}
#endregion CheckPreconditions

Write-AlpacaGroupStart "Precompile and Translate" #Level 1

#region ClearTranslations
$TranslationFolder = Join-Path $CompilationParams.Value.appProjectFolder "Translations"
if (-not (Test-Path $TranslationFolder)) {
    Write-AlpacaWarning "Translation folder $TranslationFolder does not exist."
}
Write-AlpacaOutput "Clearing existing translation files in $TranslationFolder"
Get-ChildItem $TranslationFolder -Recurse -File -Filter *.xlf | ForEach-Object {
    Write-AlpacaOutput "Removing translation file: $($_.FullName)"
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
if ($Settings.alpaca.PSObject.Properties.Name -contains 'TestTranslations' -and $Settings.alpaca.TestTranslations) {
    Test-TranslationFile -Folder $TranslationFolder -Rules $Settings.alpaca.testTranslationRules
}
#endregion Translate

Write-AlpacaGroupEnd #Level 1
