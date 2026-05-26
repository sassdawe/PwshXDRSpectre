BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Set-XdrLastInputDiagnostics' {
    It 'accepts an empty key character display for navigation keys' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{
                Diagnostics = [pscustomobject]@{ LastInput = $null }
            }
            $key = [System.ConsoleKeyInfo]::new([char]0, [System.ConsoleKey]::DownArrow, $false, $false, $false)

            { Set-XdrLastInputDiagnostics -Context $context -Key $key -InputTime (Get-Date) -KeyCharDisplay '' -ModifierSummary '0' -KeyHandled $true -ActivePanel 'incidents' -IsQueryMode $false -SelectedQueryIndex 0 } | Should -Not -Throw

            $context.Diagnostics.LastInput.KeyChar | Should -Be ''
            $context.Diagnostics.LastInput.Key | Should -Be 'DownArrow'
        }
    }
}
