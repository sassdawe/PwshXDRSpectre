BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Test-XDRPermissions' {
    It 'returns Operator when SecurityIncident.ReadWrite.All is present' {
        InModuleScope PwshXDRSpectre {
            Mock Get-MgContext {
                [pscustomobject]@{
                    TenantId = 'tenant-1'
                    Scopes   = @('User.Read', 'SecurityIncident.ReadWrite.All')
                }
            }

            $result = Test-XDRPermissions

            $result.Success | Should -BeTrue
            $result.Data.AccessLevel | Should -Be 'Operator'
            $result.Data.HasOperatorAccess | Should -BeTrue
            $result.Data.HasReaderAccess | Should -BeTrue
        }
    }

    It 'returns Reader when SecurityIncident.Read.All is present without write scope' {
        InModuleScope PwshXDRSpectre {
            Mock Get-MgContext {
                [pscustomobject]@{
                    TenantId = 'tenant-1'
                    Scopes   = @('User.Read', 'SecurityIncident.Read.All')
                }
            }

            $result = Test-XDRPermissions

            $result.Success | Should -BeTrue
            $result.Data.AccessLevel | Should -Be 'Reader'
            $result.Data.HasOperatorAccess | Should -BeFalse
            $result.Data.HasReaderAccess | Should -BeTrue
        }
    }

    It 'returns None when incident read scopes are missing' {
        InModuleScope PwshXDRSpectre {
            Mock Get-MgContext {
                [pscustomobject]@{
                    TenantId = 'tenant-1'
                    Scopes   = @('User.Read', 'SecurityAlert.ReadWrite.All')
                }
            }

            $result = Test-XDRPermissions

            $result.Success | Should -BeFalse
            $result.Data.AccessLevel | Should -Be 'None'
            $result.Data.HasOperatorAccess | Should -BeFalse
            $result.Data.HasReaderAccess | Should -BeFalse
            $result.Data.MissingScopes | Should -Contain 'SecurityIncident.Read.All'
        }
    }

    It 'refreshes permission health when context is supplied' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'

            Mock Get-MgContext {
                [pscustomobject]@{
                    TenantId = 'tenant-1'
                    Scopes   = @('User.Read', 'SecurityIncident.ReadWrite.All')
                }
            }

            $result = Test-XDRPermissions -Context $context

            $result.Success | Should -BeTrue
            $context.Session.PermissionHealth.DetectionSource | Should -Be 'graph-scope'
            $context.Session.PermissionHealth.HasSufficientWritePermissions | Should -BeTrue
            $context.Session.PermissionHealth.AvailablePermissions | Should -Contain 'securityincident.readwrite.all'
        }
    }

    It 'returns a failure result when Graph context is unavailable' {
        InModuleScope PwshXDRSpectre {
            Mock Get-MgContext {
                throw 'Graph context unavailable'
            }

            $result = Test-XDRPermissions

            $result.Success | Should -BeFalse
            $result.Data.AccessLevel | Should -Be 'None'
            $result.Data.IsConnectedToGraph | Should -BeFalse
            $result.Message | Should -Match 'No active Microsoft Graph context was found'
        }
    }

    Context 'comment-based help' {
        It 'has a Synopsis' {
            (Get-Help Test-XDRPermissions).Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'has a Description' {
            (Get-Help Test-XDRPermissions).Description | Should -Not -BeNullOrEmpty
        }
    }
}