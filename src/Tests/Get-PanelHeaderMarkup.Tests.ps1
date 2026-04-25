BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-PanelHeaderMarkup' {
    It 'renders active header markup with ACTIVE badge' {
        InModuleScope PwshXDRSpectre {
            Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel 'incidents' -Color 'orange1' | Should -Be '[bold orange1]Incident List (ACTIVE)[/]'
        }
    }

    It 'renders inactive header markup in white' {
        InModuleScope PwshXDRSpectre {
            Get-PanelHeaderMarkup -PanelName 'alerts' -Title 'Alert List' -ActivePanel 'incidents' -Color 'orange1' | Should -Be '[white]Alert List[/]'
        }
    }
}