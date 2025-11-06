param(
    [string] $appType,
    [ref] $compilationParams
)
Write-AlpacaOutput "Using COSMO Alpaca override"

#region Functions
function WriteVariables {
    param (
        [Int]$Level = 0
    )
    $vars = try { get-variable -Scope (1 + $Level) } catch {}
    if (-not $vars) {
        return
    }
    Write-AlpacaGroupStart "Custom Variables (Scope=$Level):"
    $vars  <#| where-object { (@(
                "FormatEnumerationLimit",
                "MaximumAliasCount",
                "MaximumDriveCount",
                "MaximumErrorCount",
                "MaximumFunctionCount",
                "MaximumVariableCount",
                "PGHome",
                "PGSE",
                "PGUICulture",
                "PGVersionTable",
                "PROFILE",
                "PSSessionOption"
            ) -notcontains $_.name) -and `
        (([psobject].Assembly.GetType('System.Management.Automation.SpecialVariables').GetFields('NonPublic,Static') | Where-Object FieldType -eq ([string]) | ForEach-Object GetValue $null)) -notcontains $_.name
    } #> | ForEach-Object { Write-AlpacaOutput "$($_.Name): $($_.Value)" }
    Write-AlpacaGroupEnd
}
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
    Write-AlpacaDebug "Successfully installed XliffSync module"

    Write-AlpacaOutput "Found $($Languages.Count) target languages"

    $globalXlfFiles = @() # Initialize variable to enforce an array due to strict mode
    $globalXlfFiles += Get-ChildItem -path $Folder -Include '*.g.xlf' -Recurse
    if (-not $globalXlfFiles) {
        Write-AlpacaError "No .g.xlf files found in $Folder!"
        Write-Output ("Files in directory: {0}" -f ((Get-ChildItem -path $Folder -Recurse | Select-Object -ExpandProperty FullName -ErrorAction SilentlyContinue | ForEach-Object { $_.Replace($Folder, '').TrimStart('\') } )) -join ', ')
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
    Write-AlpacaDebug "Successfully installed XliffSync module"

    $translatedXlfFiles = @() # Initialize variable to enforce an array due to strict mode
    $translatedXlfFiles += Get-ChildItem -path $Folder -Include '*.??-??.xlf' -Exclude '*.g.xlf' -Recurse
    Write-AlpacaDebug "Found $($translatedXlfFiles.Count) files in $Folder"

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
Write-AlpacaGroupStart "DebugInfo"

Write-AlpacaOutput "App Type: $appType"

Write-AlpacaGroupStart "Compilation Params:"
"$($compilationParams.Value | ConvertTo-Json -Depth 2)" -split "`n" | ForEach-Object { Write-AlpacaOutput $_ }
Write-AlpacaGroupEnd

Write-AlpacaGroupStart "Env Variables:"
Get-ChildItem Env: | ForEach-Object { Write-AlpacaOutput "  $($_.Name): $($_.Value)" }
Write-AlpacaGroupEnd

for ($i = 0; $i -lt 20; $i++) {
    WriteVariables -Level $i
}

$Settings = $env:Settings | ConvertFrom-Json
Write-Output "Settings:"
Write-Output ("Settings.alpaca.createTranslations = {0}" -f $(try { $Settings.alpaca.createTranslations }catch {}))
Write-Output ("Settings.alpaca.translationLanguages = {0}" -f $(try { $Settings.alpaca.translationLanguages -join ', ' }catch {}))
Write-Output ("Settings.alpaca.TestTranslations = {0}" -f $(try { $Settings.alpaca.TestTranslations }catch {}))
Write-Output ("Settings.alpaca.testTranslationRules = {0}" -f $(try { $Settings.alpaca.testTranslationRules -join ', ' }catch {}))

Write-AlpacaGroupEnd
#endregion DebugInfo

#region CheckPreconditions
Write-AlpacaGroupStart "Check Preconditions"
if (-not $Settings.alpaca) {
    Write-Output "No 'alpaca' settings found, skipping precompilation and translation."
    return
}
if (-not $Settings.alpaca.createTranslations) {
    Write-AlpacaOutput "Skipping precompilation and translation as 'createTranslations' setting is disabled."
    return
}
if (-not $Settings.alpaca.translationLanguages) {
    Write-AlpacaError "No translation languages configured in 'translationLanguages' setting!"
    return
}

# TODO CHeck Translation feature from app.json and algo setting
Write-AlpacaGroupEnd
#endregion CheckPreconditions

Write-AlpacaGroupStart "Precompile and Translate"

#region ClearTranslations
$TranslationFolder = Join-Path $compilationParams.Value.appProjectFolder "Translations"
if (-not (Test-Path $TranslationFolder)) {
    Write-AlpacaWarning "Translation folder $TranslationFolder does not exist."
}
Write-AlpacaDebug "Clearing existing translation files in $TranslationFolder"
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
    $appFile = Invoke-Command -ScriptBlock $CompileAppWithBcCompilerFolder -ArgumentList $compilationParamsCopy
}
else {
    $appFile = Invoke-Command -ScriptBlock $CompileAppInBcContainer -ArgumentList $compilationParamsCopy
}
#endregion PreCompile

#region Translate
New-TranslationFiles -Folder $TranslationFolder -Languages $Settings.alpaca.translationLanguages
if ($Settings.alpaca.TestTranslations) {
    Test-TranslationFiles -Folder $TranslationFolder -Rules $Settings.alpaca.testTranslationRules
}
#endregion Translate

Write-AlpacaGroupEnd
