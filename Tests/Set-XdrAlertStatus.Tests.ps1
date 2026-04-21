BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Set-XdrAlertStatus' {
    It 'builds payload for in progress alert updates' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.AlertActions = @('UpdateAlertStatus')

            Mock Update-MgSecurityAlertV2 {
                $script:lastBody = $BodyParameter
                [pscustomobject]@{ Id = $AlertId; Status = $BodyParameter.status }
            }

            $result = Set-XdrAlertStatus -Context $context -AlertId 'alert-1' -Status 'In progress' -SkipConfirmation

            $result.Success | Should -BeTrue
            $script:lastBody.status | Should -Be 'inProgress'
        }
    }

    It 'requires confirmation for reopening an alert to new' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.AlertActions = @('UpdateAlertStatus')

            $result = Set-XdrAlertStatus -Context $context -AlertId 'alert-2' -Status 'New'

            $result.Success | Should -BeFalse
            $result.Data.ConfirmationRequired | Should -BeTrue
            $result.Data.ActionName | Should -Be 'Set alert status to New'
        }
    }

    It 'fails closed when alert capability is missing' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'

            $result = Set-XdrAlertStatus -Context $context -AlertId 'alert-3' -Status 'Resolved' -SkipConfirmation

            $result.Success | Should -BeFalse
            $result.Message | Should -Be 'Capability not available: UpdateAlertStatus'
        }
    }
}