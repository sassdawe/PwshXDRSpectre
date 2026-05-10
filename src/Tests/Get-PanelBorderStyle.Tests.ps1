BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-PanelBorderStyle' {
    It 'returns Double for active panel' {
        InModuleScope PwshXDRSpectre {
            Get-PanelBorderStyle -PanelName 'help' -ActivePanel 'help' | Should -Be 'Double'
        }
    }

    It 'returns Rounded for inactive panel' {
        InModuleScope PwshXDRSpectre {
            Get-PanelBorderStyle -PanelName 'help' -ActivePanel 'incidents' | Should -Be 'Rounded'
        }
    }
}
