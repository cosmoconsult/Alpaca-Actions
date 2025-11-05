param(
    [string] $appType,
    [ref] $compilationParams
)
Write-AlpacaOutput "Using COSMO Alpaca override"

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
for ($i = 0; $i -lt 20; $i++) {
    WriteVariables -Level $i
}

Invoke-AlpacaPrecompileApp -appType $appType -compilationParams ([ref] $compilationParams.value)
