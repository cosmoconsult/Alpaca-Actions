function Invoke-AlpacaPrecompileApp {
    param(
        [string] $appType,
        [ref] $compilationParams
    )
    Write-Host "Hello from Invoke-AlpacaPrecompileApp.psm1"

    #region DebugInfo
    Write-AlpacaGroupStart "DebugInfo"

    Write-AlpacaOutput "App Type: $appType"

    Write-AlpacaGroupStart "Compilation Params:"
    "$($compilationParams.Value | ConvertTo-Json -Depth 2)" -split "`n" | ForEach-Object { Write-AlpacaOutput $_ }
    Write-AlpacaGroupEnd

    Write-AlpacaGroupStart "Env Variables:"
    Get-ChildItem Env: | ForEach-Object { Write-AlpacaOutput "  $($_.Name): $($_.Value)" }
    Write-AlpacaGroupEnd

    for ($i = 0; $i -lt 10; $i++) {
        WriteCustomVariables -Level $i
    }

    Write-AlpacaGroupEnd
    #endregion DebugInfo

    # TODO: check if xliff things configured
    Write-AlpacaGroupStart "Precompile and Translate"

    #region PreCompile

    # Remove Cops parameters
    $compilationParamsCopy = $compilationParams.Value.Clone()
    $compilationParamsCopy.Keys | Where-Object { $_ -in $CopParameters.Keys } | ForEach-Object { $compilationParamsCopy.Remove($_) }
    # TODO: Check other compilationParamsCopy
    if ($useCompilerFolder) {
        $appFile = Invoke-Command -ScriptBlock $CompileAppWithBcCompilerFolder -ArgumentList $compilationParamsCopy
    }
    else {
        $appFile = Invoke-Command -ScriptBlock $CompileAppInBcContainer -ArgumentList $compilationParamsCopy
    }
    #endregion PreCompile

    # TODO: merge xliff
    Write-AlpacaGroupEnd

}
function WriteCustomVariables {
    param (
        [Int]$Level = 0
    )
    Write-AlpacaGroupStart "Custom Variables (Scope=$Level):"
    # src: https://stackoverflow.com/a/18427474
    (try { get-variable -Scope (1 + $Level) } catch {}) | where-object { (@(
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
    } | ForEach-Object { Write-AlpacaOutput "$($_.Name): $($_.Value)" }
    Write-AlpacaGroupEnd
}

Export-ModuleMember -Function Invoke-AlpacaPrecompileApp