
Describe "PSScriptAnalyzer" {
    $TestCases = @()
    $Rules = @(
        "PSAlignAssignmentStatement",
        "PSAvoidUsingCmdletAliases",
        "PSAvoidAssignmentToAutomaticVariable",
        "PSAvoidDefaultValueSwitchParameter",
        "PSAvoidDefaultValueForMandatoryParameter",
        # "PSAvoidUsingEmptyCatchBlock", # TODO: Check and reenable if needed
        "PSAvoidExclaimOperator",
        "PSAvoidGlobalAliases",
        "PSAvoidGlobalFunctions",
        "PSAvoidGlobalVars",
        "PSAvoidInvokingEmptyMembers",
        "PSAvoidLongLines",
        "PSAvoidMultipleTypeAttributes",
        "PSAvoidNullOrEmptyHelpMessageAttribute",
        "PSAvoidOverwritingBuiltInCmdlets",
        # "PSAvoidUsingPositionalParameters", # TODO: Check and reenable if needed
        "PSReservedCmdletChar",
        "PSReservedParams",
        "PSAvoidSemicolonsAsLineTerminators",
        "PSAvoidShouldContinueWithoutForce",
        # "PSAvoidTrailingWhitespace", # TODO: Check and reenable if needed
        # "PSAvoidUsingUsernameAndPasswordParams", # TODO: Check and reenable if needed
        "PSAvoidUsingAllowUnencryptedAuthentication",
        "PSAvoidUsingBrokenHashAlgorithms",
        "PSAvoidUsingComputerNameHardcoded",
        # "PSAvoidUsingConvertToSecureStringWithPlainText", # TODO: Check and reenable if needed
        "PSAvoidUsingDeprecatedManifestFields",
        "PSAvoidUsingDoubleQuotesForConstantString",
        "PSAvoidUsingInvokeExpression",
        # "PSAvoidUsingPlainTextForPassword", # TODO: Check and reenable if needed
        "PSAvoidUsingWMICmdlet",
        # "PSAvoidUsingWriteHost", # TODO: Check and reenable if needed
        "PSUseCompatibleCommands",
        "PSUseCompatibleSyntax",
        "PSUseCompatibleTypes",
        "PSMisleadingBacktick",
        "PSMissingModuleManifestField",
        "PSPlaceCloseBrace",
        "PSPlaceOpenBrace",
        "PSPossibleIncorrectComparisonWithNull",
        "PSPossibleIncorrectUsageOfAssignmentOperator",
        "PSPossibleIncorrectUsageOfRedirectionOperator",
        # "PSProvideCommentHelp", # TODO: Check and reenable if needed
        # "PSReviewUnusedParameter", # TODO: Check and reenable if needed
        "PSUseApprovedVerbs",
        # "PSUseBOMForUnicodeEncodedFile", #Disabled because of *nix system compatibility
        "PSUseCmdletCorrectly",
        "PSUseCompatibleCmdlets",
        "PSUseConsistentIndentation",
        "PSUseConsistentWhitespace",
        "PSUseCorrectCasing",
        "PSUseDeclaredVarsMoreThanAssignments",
        "PSUseLiteralInitializerForHashtable",
        "PSUseOutputTypeCorrectly",
        "PSUseProcessBlockForPipelineCommand",
        "PSUsePSCredentialType",
        "PSShouldProcess",
        # "PSUseShouldProcessForStateChangingFunctions", # TODO: Check and reenable if needed
        # "PSUseSingularNouns", # TODO: Check and reenable if needed
        "PSUseSupportsShouldProcess",
        "PSUseToExportFieldsInManifest",
        "PSUseUsingScopeModifierInNewRunspaces",
        "PSUseUTF8EncodingForHelpFile",
        "PSDSCDscExamplesPresent",
        "PSDSCDscTestsPresent",
        "PSDSCReturnCorrectTypesForDSCFunctions",
        "PSDSCUseIdenticalMandatoryParametersForDSC",
        "PSDSCUseIdenticalParametersForDSC",
        "PSDSCStandardDSCFunctionsInResource",
        "PSDSCUseVerboseMessageInDSCResource"
    )
    $TestFiles = Join-Path $PSScriptRoot '..' 'Scripts' | Get-Item | Get-ChildItem -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1' }
    foreach ($PesterTestCase in $(Get-ScriptAnalyzerRule | Select-Object -ExpandProperty RuleName)) {
        foreach ($File in $TestFiles) {
            $TestCases += @{
                Name         = $File.Name
                FullFileName = $File.FullName
                Rule         = $PesterTestCase
                Skip         = $PesterTestCase -notin $Rules
            }
        }
    }

    foreach ($TestCase in $TestCases | Where-Object { $_.Skip }) {
        It "Test $($TestCase.Name) against $($TestCase.Rule)" -ForEach $TestCase -Skip {
        }
    }
    foreach ($TestCase in $TestCases | Where-Object { !$_.Skip }) {
        It "Test $($TestCase.Name) against $($TestCase.Rule)" -ForEach $TestCase {
            $TestResult = Invoke-ScriptAnalyzer -Path $FullFileName -IncludeRule $Rule
            if ($TestResult) {
                $ErrorMessage = "ScriptAnalyzer found issues in $($FullFileName):`n"
                foreach ($Issue in $TestResult) {
                    $ErrorMessage += "Line $($Issue.Line): $($Issue.Message)`n"
                }
                throw $ErrorMessage
            }
        }
    }
}