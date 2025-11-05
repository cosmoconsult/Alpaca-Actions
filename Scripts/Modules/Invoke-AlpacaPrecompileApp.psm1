function Invoke-AlpacaPrecompileApp {
    param(
        [string] $appType,
        [ref] $compilationParams
    )
    Write-Host "Hello from Invoke-AlpacaPrecompileApp.psm1"

    #region DebugInfo
    Write-AlpacaGroupStart "DebugInfo"

    Write-Host "App Type: $appType"

    Write-Host "Compilation Params:"
    $compilationParams.Value | ForEach-Object { Write-Host "  $_" }

    Write-Host "Env Variables:"
    Get-ChildItem Env: | ForEach-Object { "  $($_.Name): $($_.Value)" }

    Write-AlpacaGroupEnd
    #endregion DebugInfo

    # TODO: check if xliff things configured
    Write-AlpacaGroupStart "Precompile and Translate"

    #region PreCompile

    # Remove Cops parameters
    $compilationParamsCopy = $compilationParams.Clone()
    $compilationParamsCopy.Keys | Where-Object { $_ -in $CopParameters.Keys } | ForEach-Object { $compilationParams.Remove($_) }
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

Export-ModuleMember -Function Invoke-AlpacaPrecompileApp