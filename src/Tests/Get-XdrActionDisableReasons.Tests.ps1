BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrActionDisableReasons' {
    It 'returns deterministic disable reasons' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $reasons = Get-XdrActionDisableReasons -ActionName 'Set incident status to Active' -ActionType Incident -Context $context -CurrentStatus 'active' -RequestedStatus 'active'

            $reasons | Should -Contain 'Missing selection context: incident'
            $reasons | Should -Contain 'Missing capability: UpdateIncidentStatus'
            $reasons | Should -Contain 'Invalid transition for current status'
        }
    }
}