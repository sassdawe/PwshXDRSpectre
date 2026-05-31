BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Set-XdrLiveActionPanelVisibility' {
    It 'rebuilds compact layout and moves focus away from a hidden action panel' {
        InModuleScope PwshXDRSpectre {
            $layout = New-XdrLiveDashboardLayout -ActionPanelVisible
            $dashboardFrame = Format-SpectrePanel -Data $layout -Header ' ' -Color 'deepskyblue1' -Border 'Rounded' -Expand
            $screenLayout = New-SpectreLayout -Name 'screen' -Rows @(
                (New-SpectreLayout -Name 'dashboard_frame' -Ratio 1 -Data $dashboardFrame)
            )
            $tabOrder = @('incidents', 'hunting')
            $panelOrder = @('incident_list', 'incident_details', 'alert_list', 'incident_actions')
            $activePanel = 'incident_actions'
            $activePanelIndex = 3
            $context = [pscustomobject]@{
                Selection = [pscustomobject]@{ Panel = $activePanel }
            }

            Set-XdrLiveActionPanelVisibility -Visible $false -Layout ([ref]$layout) -DashboardFrame ([ref]$dashboardFrame) -ScreenLayout $screenLayout -TabOrder $tabOrder -ActiveTabIndex 0 -ActiveTab 'incidents' -PanelOrder ([ref]$panelOrder) -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -Context $context

            $layout['right_actions'] | Should -BeNullOrEmpty
            $panelOrder | Should -Be @('incident_list', 'incident_details', 'alert_list')
            $activePanel | Should -Be 'incident_list'
            $activePanelIndex | Should -Be 0
            $context.Selection.Panel | Should -Be 'incident_list'
        }
    }
}
