BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Resolve-XdrLivePanelSlot' {
    It 'maps workflow panels to physical dashboard slots' {
        InModuleScope PwshXDRSpectre {
            Resolve-XdrLivePanelSlot -PanelName 'workflow_list' | Should -Be 'left_top'
            Resolve-XdrLivePanelSlot -PanelName 'workflow_overview' | Should -Be 'center_top'
            Resolve-XdrLivePanelSlot -PanelName 'workflow_steps' | Should -Be 'left_bottom'
            Resolve-XdrLivePanelSlot -PanelName 'workflow_step_details' | Should -Be 'center_bottom'
            Resolve-XdrLivePanelSlot -PanelName 'workflow_actions' | Should -Be 'right_actions'
        }
    }
}
