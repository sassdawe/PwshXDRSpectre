BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-PanelHeaderMarkup' {
    It 'renders active header markup with ACTIVE badge' {
        InModuleScope PwshXDRSpectre {
            Get-PanelHeaderMarkup -PanelName 'incident_list' -Title 'Incident List' -ActivePanel 'incident_list' -Color 'orange1' | Should -Be '[bold orange1]Incident List (ACTIVE)[/]'
        }
    }

    It 'renders inactive header markup in white' {
        InModuleScope PwshXDRSpectre {
            Get-PanelHeaderMarkup -PanelName 'alert_list' -Title 'Alert List' -ActivePanel 'incident_list' -Color 'orange1' | Should -Be '[white]Alert List[/]'
        }
    }
}