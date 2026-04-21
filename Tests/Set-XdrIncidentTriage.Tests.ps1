BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Set-XdrIncidentTriage' {
    It 'builds status payload for in progress updates' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('UpdateIncidentStatus')

            Mock Update-MgSecurityIncident {
                $script:lastBody = $BodyParameter
                [pscustomobject]@{ Id = $IncidentId; Status = $BodyParameter.status }
            }

            $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-1' -Status 'In progress' -SkipConfirmation

            $result.Success | Should -BeTrue
            $script:lastBody.status | Should -Be 'inProgress'
        }
    }

    It 'auto-fills resolving comment when resolving without a comment' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('UpdateIncidentStatus')

            Mock Update-MgSecurityIncident {
                $script:lastBody = $BodyParameter
                [pscustomobject]@{ Id = $IncidentId; Status = $BodyParameter.status }
            }

            $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-2' -Status 'Resolved' -SkipConfirmation

            $result.Success | Should -BeTrue
            $script:lastBody.status | Should -Be 'resolved'
            $script:lastBody.comments[0].comment | Should -Be 'Incident resolved by current user using PwshXDRSpectre.'
        }
    }

    It 'uses analyst identity in auto-filled resolving comment when available' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('UpdateIncidentStatus')
            $context.Session.Analyst = [pscustomobject]@{
                DisplayName = 'Alex Analyst'
                UserPrincipalName = 'alex@contoso.com'
                Mail = 'alex@contoso.com'
            }

            Mock Update-MgSecurityIncident {
                $script:lastBody = $BodyParameter
                [pscustomobject]@{ Id = $IncidentId; Status = $BodyParameter.status }
            }

            $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-2b' -Status 'Resolved' -SkipConfirmation

            $result.Success | Should -BeTrue
            $script:lastBody.status | Should -Be 'resolved'
            $script:lastBody.comments[0].comment | Should -Be 'Incident resolved by Alex Analyst using PwshXDRSpectre.'
        }
    }

    It 'requires confirmation for resolved incident status when not skipped' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('UpdateIncidentStatus')

            $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-3' -Status 'Resolved'

            $result.Success | Should -BeFalse
            $result.Data.ConfirmationRequired | Should -BeTrue
            $result.Data.ActionName | Should -Be 'Set incident status to Resolved'
        }
    }

    It 'uses mail then user principal name when assigning to me' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('AssignIncident')
            $context.Session.Analyst = [pscustomobject]@{
                Mail = ''
                UserPrincipalName = 'analyst@contoso.com'
            }

            Mock Update-MgSecurityIncident {
                $script:lastBody = $BodyParameter
                [pscustomobject]@{ Id = $IncidentId; AssignedTo = $BodyParameter.assignedTo }
            }

            $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-4' -AssignToMe -SkipConfirmation

            $result.Success | Should -BeTrue
            $script:lastBody.assignedTo | Should -Be 'analyst@contoso.com'
        }
    }

    It 'fails closed when incident status capability is missing' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'

            $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-5' -Status 'Active' -SkipConfirmation

            $result.Success | Should -BeFalse
            $result.Message | Should -Be 'Capability not available: UpdateIncidentStatus'
        }
    }
}