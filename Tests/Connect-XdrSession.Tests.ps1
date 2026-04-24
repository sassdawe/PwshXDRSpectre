BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Connect-XdrSession' {
    It 'keeps write mode when SecurityIncident.ReadWrite.All is present' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'

            Mock Connect-MgGraph {
                [pscustomobject]@{ Connected = $true }
            }

            Mock Get-XdrCurrentUser {
                [pscustomobject]@{
                    Success = $true
                    Data    = [pscustomobject]@{ DisplayName = 'Alex Analyst' }
                }
            }

            Mock Get-MgContext {
                [pscustomobject]@{
                    Scopes = @(
                        'User.Read',
                        'SecurityIncident.ReadWrite.All'
                    )
                }
            }

            $result = Connect-XdrSession -Context $context

            $result.Success | Should -BeTrue
            $context.Session.PermissionHealth.HasSufficientWritePermissions | Should -BeTrue
            $context.Session.PermissionHealth.DetectionSource | Should -Be 'graph-scope'
            $context.Session.PermissionHealth.RequiredPermissions.Count | Should -Be 0
            $context.Session.PermissionHealth.AvailablePermissions | Should -Contain 'SecurityIncident.ReadWrite.All'
            $context.Capabilities.IncidentActions.Count | Should -BeGreaterThan 0
            $context.Capabilities.AlertActions | Should -Contain 'UpdateAlertStatus'
        }
    }

    It 'switches to read-only mode when SecurityIncident.ReadWrite.All is missing' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'

            Mock Connect-MgGraph {
                [pscustomobject]@{ Connected = $true }
            }

            Mock Get-XdrCurrentUser {
                [pscustomobject]@{
                    Success = $true
                    Data    = [pscustomobject]@{ DisplayName = 'Alex Analyst' }
                }
            }

            Mock Get-MgContext {
                [pscustomobject]@{
                    Scopes = @(
                        'User.Read',
                        'SecurityAlert.ReadWrite.All'
                    )
                }
            }

            $result = Connect-XdrSession -Context $context

            $result.Success | Should -BeTrue
            $context.Session.PermissionHealth.HasSufficientWritePermissions | Should -BeFalse
            $context.Session.PermissionHealth.DetectionSource | Should -Be 'graph-scope'
            $context.Session.PermissionHealth.RequiredPermissions | Should -Contain 'SecurityIncident.ReadWrite.All'
            $context.Capabilities.IncidentActions.Count | Should -Be 0
            $context.Capabilities.AlertActions | Should -Be @('GetAlerts')
        }
    }

    Context 'comment-based help' {
        It 'has a Synopsis' {
            (Get-Help Connect-XdrSession).Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'has a Description' {
            (Get-Help Connect-XdrSession).Description | Should -Not -BeNullOrEmpty
        }
    }
}
