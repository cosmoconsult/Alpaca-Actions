#-------------------------------------------------------------------------
#---     Copyright (c) COSMO CONSULT.  All rights reserved.            ---
#-------------------------------------------------------------------------

@{

    # Script module or binary module file associated with this manifest.
    # RootModule = ''

    # Version number of this module.
    ModuleVersion        = '1.0'

    # ID used to uniquely identify this module
    GUID                 = 'b5c30b56-84af-4616-b79e-be24bbb4af28'

    # Author of this module
    Author               = 'COSMO CONSULT'

    # Company or vendor of this module
    CompanyName          = 'COSMO CONSULT'

    # Copyright statement for this module
    Copyright            = '© 2025 COSMO CONSULT. All rights reserved.'

    # Supported PSEditions
    CompatiblePSEditions = @('Core')

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion    = '7.0'

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    ScriptsToProcess     = @('Alpaca.ps1')

    NestedModules        = @(
        'API-Helper.psm1',
        'Find-ALGoSettingsFiles.psm1',
        'Find-SecretsToSyncInObject.psm1',
        'Get-AlpacaDependencyApps.psm1',
        'Get-AlpacaConfigSyncStatus.psm1',
        'New-AlpacaContainer.psm1',
        'Output-Helper.psm1',
        'Publish-AlpacaBcApp.psm1',
        'Get-AlpacaAppInfo.psm1',
        'Get-AlpacaContainer.psm1',
        'Remove-AlpacaContainer.psm1',
        'Sync-AlpacaConfigs.psm1',
        'Wait-AlpacaContainerImageReady.psm1',
        'Translation-Helper.psm1',
        'AL-Go-Helper.psm1',
        'Wait-AlpacaContainerReady.psm1',
        'Read-AppManifest.psm1')

    # Functions to export from this module
    FunctionsToExport    = '*'

    # Cmdlets to export from this module
    CmdletsToExport      = '*'

    # Variables to export from this module
    VariablesToExport    = '*'

    # Aliases to export from this module
    AliasesToExport      = '*'
}
