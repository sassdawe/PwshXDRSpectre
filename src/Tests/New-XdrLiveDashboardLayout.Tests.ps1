BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'New-XdrLiveDashboardLayout' {
    It 'builds the normal layout with the right action column' {
        InModuleScope PwshXDRSpectre {
            $layout = New-XdrLiveDashboardLayout -ActionPanelVisible

            $layout['left_top'] | Should -Not -BeNullOrEmpty
            $layout['center_top'] | Should -Not -BeNullOrEmpty
            $layout['right_actions'] | Should -Not -BeNullOrEmpty
            $layout['help'] | Should -Not -BeNullOrEmpty
        }
    }

    It 'builds compact layout without the right action column' {
        InModuleScope PwshXDRSpectre {
            $layout = New-XdrLiveDashboardLayout

            $layout['left_top'] | Should -Not -BeNullOrEmpty
            $layout['center_top'] | Should -Not -BeNullOrEmpty
            $layout['right_actions'] | Should -BeNullOrEmpty
            $layout['help'] | Should -Not -BeNullOrEmpty
        }
    }
}
