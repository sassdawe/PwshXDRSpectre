BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-PanelBorderColor' {
    It 'returns accent for active panel' {
        InModuleScope PwshXDRSpectre {
            Get-PanelBorderColor -PanelName 'help' -ActivePanel 'help' -AccentColor 'orange1' | Should -Be 'orange1'
        }
    }

    It 'returns base color for inactive panel' {
        InModuleScope PwshXDRSpectre {
            Get-PanelBorderColor -PanelName 'help' -ActivePanel 'incident_list' -AccentColor 'orange1' | Should -Be 'deepskyblue1'
        }
    }
}