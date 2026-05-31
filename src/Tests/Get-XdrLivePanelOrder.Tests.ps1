BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrLivePanelOrder' {
    It 'includes action panels by default' {
        InModuleScope PwshXDRSpectre {
            Get-XdrLivePanelOrder -TabName 'incidents' | Should -Contain 'incident_actions'
            Get-XdrLivePanelOrder -TabName 'hunting' | Should -Contain 'query_actions'
            Get-XdrLivePanelOrder -TabName 'workflows' | Should -Contain 'workflow_actions'
        }
    }

    It 'removes action panels when compact layout hides the action column' {
        InModuleScope PwshXDRSpectre {
            $incidentOrder = @(Get-XdrLivePanelOrder -TabName 'incidents' -HideActionPanel)
            $huntingOrder = @(Get-XdrLivePanelOrder -TabName 'hunting' -HideActionPanel)
            $workflowOrder = @(Get-XdrLivePanelOrder -TabName 'workflows' -HideActionPanel)

            $incidentOrder | Should -Be @('incident_list', 'incident_details', 'alert_list')
            $incidentOrder | Should -Not -Contain 'incident_actions'
            $huntingOrder | Should -Be @('query_catalog', 'query_preview', 'query_activity')
            $huntingOrder | Should -Not -Contain 'query_actions'
            $workflowOrder | Should -Be @('workflow_list', 'workflow_overview', 'workflow_steps', 'workflow_step_details')
            $workflowOrder | Should -Not -Contain 'workflow_actions'
        }
    }
}
