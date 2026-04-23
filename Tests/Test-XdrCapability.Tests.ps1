BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Test-XdrCapability' {
    It 'fails closed when context is missing' {
        InModuleScope PwshXDRSpectre {
            Test-XdrCapability -CapabilityName 'AssignIncident' -Context $null | Should -BeFalse
        }
    }

    It 'throws when ThrowOnUnknown is set and context is missing' {
        InModuleScope PwshXDRSpectre {
            { Test-XdrCapability -CapabilityName 'AssignIncident' -Context $null -ThrowOnUnknown } | Should -Throw
        }
    }

    It 'returns true when capability exists' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('AssignIncident')

            Test-XdrCapability -CapabilityName 'AssignIncident' -Context $context | Should -BeTrue
        }
    }
}
