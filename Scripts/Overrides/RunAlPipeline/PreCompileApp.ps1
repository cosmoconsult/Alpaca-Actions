param(
    [string] $AppType,
    [ref] $CompilationParams
)
Write-AlpacaOutput "Using COSMO Alpaca override"

$settings = $env:Settings | ConvertFrom-Json
$alpacaSettings = Get-AlpacaALGoSettings -Settings $settings

#region DebugInfo
if (Get-AlpacaIsDebugMode) {
    Write-AlpacaGroupStart "DebugInfo" #Level 1
    Write-AlpacaDebug "App Type: $AppType"

    Write-AlpacaGroupStart "Compilation Params:" #Level 2
    $compilationParamsForDebug = [ordered]@{}
    foreach ($key in $CompilationParams.Value.Keys) {
        if ($CompilationParams.Value[$key] -is [scriptblock]) {
            $compilationParamsForDebug[$key] = "{ScriptBlock}"
        }
        else {
            $compilationParamsForDebug[$key] = $CompilationParams.Value[$key]
        }
    }
    "$($compilationParamsForDebug | ConvertTo-Json -Depth 2)" -split "`n" | ForEach-Object { Write-AlpacaDebug $_ }
    Write-AlpacaGroupEnd #Level 2
    Write-AlpacaGroupEnd #Level 1
}
#endregion DebugInfo

#region CheckIfExternalRulesetsAreSupported
Write-AlpacaGroupStart "Check if external rulesets are supported" #Level 1
try {
    $enableExternalRulesets = $CompilationParams.Value.Keys -contains 'EnableExternalRulesets' -and [bool]$CompilationParams.Value['EnableExternalRulesets']
    if ($enableExternalRulesets -and $CompilationParams.Value.Keys -contains 'compilerFolder') {
        Write-AlpacaDebug "EnableExternalRulesets is set to true and compilerFolder is specified. Checking compiler version..."
        $compilerPackageJsonPath = Join-Path -Path $CompilationParams.Value['compilerFolder'] -ChildPath 'compiler' -AdditionalChildPath 'extension', 'package.json'
        if (Test-Path $compilerPackageJsonPath) {
            $compilerVersion = [System.Version]((Get-Content -Raw -Encoding UTF8 $compilerPackageJsonPath | ConvertFrom-Json).version)
            Write-AlpacaDebug "Compiler version: $compilerVersion"
            if ($compilerVersion.Major -lt 11) {
                Write-AlpacaOutput "Compiler version $compilerVersion does not support EnableExternalRulesets. Removing the setting."
                $null = $CompilationParams.Value.Remove('EnableExternalRulesets')
            }
            else {
                Write-AlpacaOutput "Compiler version $compilerVersion supports EnableExternalRulesets. Nothing to do."
            }
        }
        else {
            Write-AlpacaOutput "Compiler package.json not found at $compilerPackageJsonPath. Cannot determine compiler version."
        }
    }
    else {
        Write-AlpacaOutput "EnableExternalRulesets is not set or compilerFolder is not specified. Skipping compiler version check."
    }
}
finally {
    Write-AlpacaGroupEnd #Level 1
}
#endregion CheckIfExternalRulesetsAreSupported

#region CustomSettingsForTestApps
Write-AlpacaGroupStart "Custom Settings For Test Apps" #Level 1
try {
    if ($AppType -in @('testApp', 'bcptApp') -and $settings.enableCodeAnalyzersOnTestApps) {
        $analyzerToggleMappings = @(
            @{ CompilationParamKey = 'enableCodeCop'; AlpacaSettingKey = 'enableCodeCopForTestApps' }
            @{ CompilationParamKey = 'enableUICop'; AlpacaSettingKey = 'enableUICopForTestApps' }
            @{ CompilationParamKey = 'enablePerTenantExtensionCop'; AlpacaSettingKey = 'enablePerTenantExtensionCopForTestApps' }
            @{ CompilationParamKey = 'enableAppSourceCop'; AlpacaSettingKey = 'enableAppSourceCopForTestApps' }
        )

        foreach ($mapping in $analyzerToggleMappings) {
            $compilationParamKey = $mapping.CompilationParamKey
            $alpacaSettingKey = $mapping.AlpacaSettingKey

            Write-AlpacaDebug "Looking for $compilationParamKey..."

            $currentValue = $null
            if ($CompilationParams.Value.Keys -contains $compilationParamKey) {
                $currentValue = $CompilationParams.Value[$compilationParamKey]
            }

            $targetValue = $alpacaSettings.$alpacaSettingKey
            if ($targetValue -notin $currentValue, $null) {
                Write-AlpacaOutput ("Overriding {0} for test apps: {1} -> {2}" -f $compilationParamKey, (ConvertTo-AlpacaOutputString -ReplaceNullAndEmptyString -Value $currentValue), (ConvertTo-AlpacaOutputString -ReplaceNullAndEmptyString -Value $targetValue))
                $CompilationParams.Value[$compilationParamKey] = $targetValue
            }
            else {
                Write-AlpacaDebug "$compilationParamKey for test apps is the same as the default setting: $targetValue"
            }
        }

        Write-AlpacaDebug "Looking for customCodeCops..."
        $currentCustomCodeCops = @()
        if ($CompilationParams.Value.Keys -contains 'customCodeCops') {
            Write-AlpacaDebug "CompilationParams contains customCodeCops."
            $currentCustomCodeCops = $CompilationParams.Value.customCodeCops
        }
        else {
            Write-AlpacaDebug "CompilationParams does not contain customCodeCops."
        }
        Write-AlpacaDebug "Comparing current customCodeCops."
        $customCodeCopsForTestApps = $alpacaSettings.customCodeCopsForTestApps
        $customCodeCopsForTestApps = @($customCodeCopsForTestApps | ForEach-Object { CheckRelativePath -baseFolder $baseFolder -sharedFolder $sharedFolder -path $_ -name "customCodeCopsForTestApps" } | Where-Object { $_ -and ($_ -like 'https://*' -or (Test-Path $_)) } )

        if (Compare-Object -ReferenceObject $customCodeCopsForTestApps -DifferenceObject $currentCustomCodeCops) {
            Write-AlpacaOutput ("Overriding customCodeCops for test apps: {0} -> {1}" -f (ConvertTo-AlpacaOutputString -ReplaceNullAndEmptyString -Value $currentCustomCodeCops), (ConvertTo-AlpacaOutputString -ReplaceNullAndEmptyString -Value $alpacaSettings.customCodeCopsForTestApps))
            if (@($customCodeCopsForTestApps).Count -eq 0) {
                Write-AlpacaDebug "Removing customCodeCops from CompilationParams."
                $null = $CompilationParams.Value.Remove('customCodeCops')
            }
            else {
                Write-AlpacaDebug "Setting customCodeCops in CompilationParams."
                $CompilationParams.Value.customCodeCops = $customCodeCopsForTestApps
            }
        }
        else {
            Write-AlpacaDebug ("customCodeCops for test apps is the same as the default setting: {0}" -f (ConvertTo-AlpacaOutputString -ReplaceNullAndEmptyString -Value $customCodeCopsForTestApps))
        }

        Write-AlpacaDebug "Looking for rulesetFile..."
        $currentRuleSetFile = $null
        if ($CompilationParams.Value.Keys -contains 'ruleset') {
            $currentRuleSetFile = $CompilationParams.Value.ruleset
        }
        $rulesetFileForTestApps = $alpacaSettings.rulesetFileForTestApps
        $rulesetFileForTestApps = CheckRelativePath -baseFolder $baseFolder -sharedFolder $sharedFolder -path $rulesetFileForTestApps -name "rulesetFileForTestApps"

        # AlpacaSettings.rulesetFileForTestApps is empty if not set
        # CurrentRuleSetFile is null when not set
        if (([string]$currentRuleSetFile) -cne ([string]$rulesetFileForTestApps)) {
            Write-AlpacaOutput "Overriding rulesetFile for test apps: $($currentRuleSetFile) -> $($rulesetFileForTestApps)"
            $CompilationParams.Value.ruleset = $rulesetFileForTestApps
        }
        else {
            Write-AlpacaDebug "rulesetFile for test apps is the same as the default setting: $($rulesetFileForTestApps)"
        }
    }
    else {
        Write-AlpacaDebug "Not a test app or bcpt app, or enableCodeAnalyzersOnTestApps is not set. No custom settings applied."
    }
}
finally {
    Write-AlpacaGroupEnd #Level 1
}
#endregion CustomSettingsForTestApps

#region ConfigureAppSourceCopSettings
Write-AlpacaGroupStart "Configure AppSourceCop settings" #Level 1
try {
    $enableAppSourceCop = $CompilationParams.Value.Keys -contains 'enableAppSourceCop' -and [bool]$CompilationParams.Value.enableAppSourceCop
    if (-not $enableAppSourceCop) {
        Write-AlpacaDebug "AppSourceCop is not enabled. No AppSourceCop settings file changes required."
    }
    elseif ($CompilationParams.Value.Keys -notcontains 'appProjectFolder') {
        Write-AlpacaWarning "Compilation params do not contain appProjectFolder. Cannot configure AppSourceCop settings file."
    }
    else {
        $obsoleteTagVersion = [string]$alpacaSettings.obsoleteTagVersion
        $obsoleteTagPattern = [string]$alpacaSettings.obsoleteTagPattern

        $shouldConfigureMandatoryAffixesForTestApps = $AppType -in @('testApp', 'bcptApp') -and $settings.enableCodeAnalyzersOnTestApps
        $appSourceCopMandatoryAffixes = if ($shouldConfigureMandatoryAffixesForTestApps) { @($settings.AppSourceCopMandatoryAffixes) } else { @() }

        $shouldSetMandatoryAffixes = $shouldConfigureMandatoryAffixesForTestApps -and $null -ne $settings.AppSourceCopMandatoryAffixes
        $shouldSetObsoleteTagVersion = -not [string]::IsNullOrWhiteSpace($obsoleteTagVersion)
        $shouldSetObsoleteTagPattern = -not [string]::IsNullOrWhiteSpace($obsoleteTagPattern)
        if (-not ($shouldSetMandatoryAffixes -or $shouldSetObsoleteTagVersion -or $shouldSetObsoleteTagPattern)) {
            Write-AlpacaDebug "No AppSourceCop settings configured by Alpaca."
        }
        else {
            $appProjectFolder = $CompilationParams.Value.appProjectFolder
            $appSourceCopJsonPath = Join-Path -Path $appProjectFolder -ChildPath 'AppSourceCop.json'

            $appSourceCopSettings = [ordered]@{}
            if (Test-Path -Path $appSourceCopJsonPath) {
                try {
                    $appSourceCopSettings = @((Get-Content -Path $appSourceCopJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable))
                    if (-not $appSourceCopSettings) {
                        $appSourceCopSettings = [ordered]@{}
                    }
                    else {
                        $appSourceCopSettings = $appSourceCopSettings[0]
                    }
                }
                catch {
                    Write-AlpacaWarning "Unable to parse AppSourceCop settings file '$appSourceCopJsonPath'. Recreating file. Error: $($_.Exception.Message)"
                    $appSourceCopSettings = [ordered]@{}
                }
            }

            $appSourceCopChanged = $false
            if ($shouldSetMandatoryAffixes) {
                $currentMandatoryAffixes = if ($appSourceCopSettings.Contains('mandatoryAffixes')) { @($appSourceCopSettings['mandatoryAffixes']) } else { @() }
                $mandatoryAffixesChanged = ($currentMandatoryAffixes.Count -ne $appSourceCopMandatoryAffixes.Count) -or (($currentMandatoryAffixes -join "`n") -cne ($appSourceCopMandatoryAffixes -join "`n"))
                if ($mandatoryAffixesChanged) {
                    Write-AlpacaOutput "Setting AppSourceCop mandatoryAffixes for test apps."
                    $appSourceCopSettings.mandatoryAffixes = $appSourceCopMandatoryAffixes
                    $appSourceCopChanged = $true
                }
            }
            $currentObsoleteTagVersion = if ($appSourceCopSettings.Contains('obsoleteTagVersion')) { [string]$appSourceCopSettings['obsoleteTagVersion'] } else { '' }
            if ($shouldSetObsoleteTagVersion -and $currentObsoleteTagVersion -cne $obsoleteTagVersion) {
                Write-AlpacaOutput "Setting AppSourceCop obsoleteTagVersion."
                $appSourceCopSettings.obsoleteTagVersion = $obsoleteTagVersion
                $appSourceCopChanged = $true
            }
            $currentObsoleteTagPattern = if ($appSourceCopSettings.Contains('obsoleteTagPattern')) { [string]$appSourceCopSettings['obsoleteTagPattern'] } else { '' }
            if ($shouldSetObsoleteTagPattern -and $currentObsoleteTagPattern -cne $obsoleteTagPattern) {
                Write-AlpacaOutput "Setting AppSourceCop obsoleteTagPattern."
                $appSourceCopSettings.obsoleteTagPattern = $obsoleteTagPattern
                $appSourceCopChanged = $true
            }

            if ($appSourceCopChanged) {
                Write-AlpacaOutput "Writing AppSourceCop settings to $appSourceCopJsonPath."
                $appSourceCopSettings | ConvertTo-Json -Depth 99 | Set-Content -Path $appSourceCopJsonPath -Encoding UTF8
            }
            else {
                Write-AlpacaDebug "AppSourceCop settings already up to date."
            }
        }
    }
}
finally {
    Write-AlpacaGroupEnd #Level 1
}
#endregion ConfigureAppSourceCopSettings

#region CheckPreconditionsForTranslation
Write-AlpacaGroupStart "Check Preconditions for Translation" #Level 1
try {
    $translate = $alpacaSettings.createTranslations
    $testTranslation = $alpacaSettings.testTranslations

    if (!($translate -or $testTranslation)) {
        Write-AlpacaOutput "Neither 'createTranslations' nor 'testTranslations' is enabled in settings, skipping translation and testing translations."
    }

    if ($translate -and $alpacaSettings.translationLanguages.Count -eq 0) {
        throw "No translation languages configured in 'translationLanguages' setting!"
    }

    if ($translate -or $testTranslation) {
        $translationEnabledInAppJson = $AppJson.PSObject.Properties.Name -contains 'features' -and $AppJson.features -contains 'TranslationFile' #AppJson comes from parent script
        Write-AlpacaOutput "Translation enabled in app.json: $translationEnabledInAppJson"
        $translationEnforcedByPipelineSetting = $CompilationParams.Value.Keys -contains 'features' -and $CompilationParams.Value.features -contains 'TranslationFile' #Set by buildmodes=Translated
        Write-AlpacaOutput "Translation enforced by pipeline setting: $translationEnforcedByPipelineSetting"
        if (-not ($translationEnabledInAppJson -or $translationEnforcedByPipelineSetting)) {
            Write-AlpacaWarning "Translation feature is not enabled in app.json or enforced by pipeline settings. Skipping translation and testing translations."
            $translate = $false
            $testTranslation = $false
        }
    }

}
finally {
    Write-AlpacaGroupEnd #Level 1
}
#endregion CheckPreconditionsForTranslation

if ($translate) {
    Write-AlpacaGroupStart "Translate" #Level 1
    try {
        $translationsFolder = Join-Path $CompilationParams.Value.appProjectFolder "Translations"

        #region ClearTranslations
        if (Test-Path $translationsFolder) {
            Write-AlpacaOutput "Clearing existing translation files in $translationsFolder"
            Get-ChildItem $translationsFolder -Recurse -File -Filter *.xlf | Where-Object { $_.BaseName.EndsWith('.g') -or $alpacaSettings.translationLanguages -contains $_.BaseName.split('.')[-1] } | ForEach-Object {
                Write-AlpacaDebug "Removing translation file: $($_.FullName)"
                Remove-Item $_.FullName -Force -Confirm:$false
            }
        }
        #endregion ClearTranslations

        #region PreCompile
        Write-AlpacaGroupStart "Pre-Compile App to generate global translation file" #Level 2
        try {
            Write-AlpacaOutput "Minimized parameters to speed up compilation"
            $compilationParamsCopy = $CompilationParams.Value.Clone()
            $compilationParamsCopy.OutputTo = { param($Line) Write-Host $Line }

            # Disable all cops
            $compilationParamsCopy.EnableCodeCop = $false
            $compilationParamsCopy.EnableAppSourceCop = $false
            $compilationParamsCopy.EnablePerTenantExtensionCop = $false
            $compilationParamsCopy.EnableUICop = $false
            $compilationParamsCopy.CustomCodeCops = @()

            # Disable all non-mandatory steps
            $compilationParamsCopy.UpdateDependencies = $false
            $compilationParamsCopy.CopyAppToSymbolsFolder = $false
            $compilationParamsCopy.GenerateReportLayout = 'No'
            $compilationParamsCopy.Generatecrossreferences = $false

            if ($useCompilerFolder) {
                #useCompilerFolder comes from parent scope
                Invoke-Command -ScriptBlock $CompileAppWithBcCompilerFolder -ArgumentList $compilationParamsCopy *>&1 | Invoke-AlpacaOutputHandler | Out-Null
            }
            else {
                Invoke-Command -ScriptBlock $CompileAppInBcContainer -ArgumentList $compilationParamsCopy *>&1 | Invoke-AlpacaOutputHandler | Out-Null
            }
        }
        finally {
            Write-AlpacaGroupEnd #Level 2
        }
        #endregion PreCompile

        New-TranslationFiles -Folder $translationsFolder -Languages $alpacaSettings.translationLanguages
    }
    finally {
        Write-AlpacaGroupEnd #Level 1
    }
}

if ($testTranslation) {
    #region TestTranslations
    Write-AlpacaGroupStart "Test Translations" #Level 1
    try {
        $translationsFolder = Join-Path $CompilationParams.Value.appProjectFolder "Translations"
        Test-TranslationFiles -Folder $translationsFolder -Rules $alpacaSettings.testTranslationRules
    }
    finally {
        Write-AlpacaGroupEnd #Level 1
    }
    #endregion TestTranslations
}

#region DebugInfo
if (Get-AlpacaIsDebugMode) {
    Write-AlpacaGroupStart "Compilation Params:" #Level 1
    $compilationParamsForDebug = [ordered]@{}
    foreach ($key in $CompilationParams.Value.Keys) {
        if ($CompilationParams.Value[$key] -is [scriptblock]) {
            $compilationParamsForDebug[$key] = "{ScriptBlock}"
        }
        else {
            $compilationParamsForDebug[$key] = $CompilationParams.Value[$key]
        }
    }
    "$($compilationParamsForDebug | ConvertTo-Json -Depth 2)" -split "`n" | ForEach-Object { Write-AlpacaDebug $_ }
    Write-AlpacaGroupEnd #Level 1
}
#endregion DebugInfo
