BeforeDiscovery {
    $overridesPath = Join-Path $PSScriptRoot '..' 'Scripts' 'Overrides' 'RunAlPipeline'
    $overrideFiles = Get-ChildItem -Path $overridesPath -Filter '*.ps1' -File
    $testCases = $overrideFiles | ForEach-Object { @{ FileName = $_.Name; FilePath = $_.FullName } }
}

Describe 'RunAlPipeline Overrides' {
    Context 'Script Content Validation' {
        It '<FileName> should have ScriptBlock content' -TestCases $testCases {
            param($FileName, $FilePath)
            
            # Act
            $scriptBlock = Get-Command $FilePath | Select-Object -ExpandProperty ScriptBlock
            
            # Assert
            $scriptBlock | Should -Not -BeNullOrEmpty
            $scriptBlock.ToString().Trim() | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Override Directory' {
        It 'Should contain at least one override file' {
            # Arrange
            $overridesPath = Join-Path $PSScriptRoot '..' 'Scripts' 'Overrides' 'RunAlPipeline'
            $overrideFiles = Get-ChildItem -Path $overridesPath -Filter '*.ps1' -File
            
            # Act & Assert
            $overrideFiles.Count | Should -BeGreaterThan 0
        }
    }
}
