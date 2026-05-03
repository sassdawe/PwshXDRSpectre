BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Set-ContextPermissionHealthFromGraphContext' {
    It 'returns without throwing when runtime context has no Session' {
        InModuleScope PwshXDRSpectre {
            $contextWithoutSession = [pscustomobject]@{
                Capabilities = [pscustomobject]@{
                    IncidentActions = @('GetIncidents')
                    AlertActions    = @('GetAlerts')
                }
            }

            { Set-ContextPermissionHealthFromGraphContext -RuntimeContext $contextWithoutSession } | Should -Not -Throw
        }
    }

    It 'creates PermissionHealth and marks read-only when incident write scope is missing' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Session.PSObject.Properties.Remove('PermissionHealth')
            $context.Capabilities.IncidentActions = @('GetIncidents', 'UpdateIncidentStatus')
            $context.Capabilities.AlertActions = @('GetAlerts', 'UpdateAlertStatus')

            Mock Get-MgContext {
                [pscustomobject]@{
                    Scopes = @(
                        'User.Read',
                        ' SecurityAlert.ReadWrite.All ',
                        '',
                        'User.Read'
                    )
                }
            }

            Set-ContextPermissionHealthFromGraphContext -RuntimeContext $context

            $context.Session.PermissionHealth | Should -Not -BeNullOrEmpty
            $context.Session.PermissionHealth.DetectionSource | Should -Be 'graph-scope'
            $context.Session.PermissionHealth.HasSufficientWritePermissions | Should -BeFalse
            $context.Session.PermissionHealth.RequiredPermissions | Should -Be @('SecurityIncident.ReadWrite.All')
            $context.Session.PermissionHealth.AvailablePermissions | Should -Contain 'user.read'
            $context.Session.PermissionHealth.AvailablePermissions | Should -Contain 'securityalert.readwrite.all'
            $context.Session.PermissionHealth.AvailablePermissions.Count | Should -Be 2
            $context.Session.PermissionHealth.LastUpdatedAt | Should -Not -BeNullOrEmpty
            $context.Capabilities.IncidentActions.Count | Should -Be 0
            $context.Capabilities.AlertActions | Should -Be @('GetAlerts')
        }
    }

    It 'keeps write mode when SecurityIncident.ReadWrite.All is available' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('GetIncidents', 'UpdateIncidentStatus')
            $context.Capabilities.AlertActions = @('GetAlerts', 'UpdateAlertStatus')

            Mock Get-MgContext {
                [pscustomobject]@{
                    Scopes = @('User.Read', 'SecurityIncident.ReadWrite.All')
                }
            }

            Set-ContextPermissionHealthFromGraphContext -RuntimeContext $context

            $context.Session.PermissionHealth.HasSufficientWritePermissions | Should -BeTrue
            $context.Session.PermissionHealth.DetectionSource | Should -Be 'graph-scope'
            $context.Session.PermissionHealth.RequiredPermissions.Count | Should -Be 0
            $context.Session.PermissionHealth.AvailablePermissions | Should -Contain 'securityincident.readwrite.all'
            $context.Capabilities.IncidentActions | Should -Contain 'UpdateIncidentStatus'
            $context.Capabilities.AlertActions | Should -Contain 'UpdateAlertStatus'
        }
    }

    It 'treats Get-MgContext failures as no-scope and leaves write mode as sufficient' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'

            Mock Get-MgContext {
                throw 'Graph context unavailable'
            }

            Set-ContextPermissionHealthFromGraphContext -RuntimeContext $context

            $context.Session.PermissionHealth.HasSufficientWritePermissions | Should -BeTrue
            $context.Session.PermissionHealth.DetectionSource | Should -Be 'graph-scope'
            $context.Session.PermissionHealth.RequiredPermissions.Count | Should -Be 0
            $context.Session.PermissionHealth.AvailablePermissions.Count | Should -Be 0
            $context.Session.PermissionHealth.LastUpdatedAt | Should -Not -BeNullOrEmpty
        }
    }
}
