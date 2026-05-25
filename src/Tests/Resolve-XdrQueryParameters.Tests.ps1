BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Resolve-XdrQueryParameters' {
    It 'resolves bound parameters from the selected incident and entity context' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Selection.Incident = [pscustomobject]@{ IncidentId = 'inc-42' }
            $context.Selection.Entity = [pscustomobject]@{ UserId = '11111111-2222-3333-4444-555555555555' }
            $query = [pscustomobject]@{
                requiredContext = @('IncidentId', 'UserId')
                parameters      = @(
                    [pscustomobject]@{ name = 'IncidentId'; contextBinding = 'IncidentId' },
                    [pscustomobject]@{ name = 'UserId'; contextBinding = 'UserId' },
                    [pscustomobject]@{ name = 'LookbackDays'; contextBinding = $null; defaultValue = '7' }
                )
            }

            $result = Resolve-XdrQueryParameters -Query $query -Context $context

            $result.Success | Should -BeTrue
            $result.IsBlocked | Should -BeFalse
            $result.Parameters['IncidentId'] | Should -Be 'inc-42'
            $result.Parameters['UserId'] | Should -Be '11111111-2222-3333-4444-555555555555'
            $result.Parameters['LookbackDays'] | Should -Be '7'
        }
    }

    It 'returns a blocked state with the missing required context keys' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Selection.Incident = [pscustomobject]@{ IncidentId = 'inc-42' }
            $query = [pscustomobject]@{
                requiredContext = @('IncidentId', 'DeviceId')
                parameters      = @(
                    [pscustomobject]@{ name = 'IncidentId'; contextBinding = 'IncidentId' },
                    [pscustomobject]@{ name = 'DeviceId'; contextBinding = 'DeviceId' }
                )
            }

            $result = Resolve-XdrQueryParameters -Query $query -Context $context

            $result.Success | Should -BeFalse
            $result.IsBlocked | Should -BeTrue
            $result.MissingContext | Should -Be @('DeviceId')
            $result.Message | Should -Be 'Missing required query context: DeviceId'
        }
    }

    It 'resolves identifiers from raw Graph evidence when the selected entity is display-only' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Selection.Entity = [pscustomobject]@{
                EntityType  = 'User'
                DisplayName = 'graph.user@contoso.com'
                RawObject   = [pscustomobject]@{
                    AdditionalProperties = @{
                        '@odata.type' = '#microsoft.graph.security.userEvidence'
                        userAccount   = @{
                            userPrincipalName = 'graph.user@contoso.com'
                            azureAdUserId     = '11111111-2222-3333-4444-555555555555'
                        }
                    }
                }
            }

            $query = [pscustomobject]@{
                requiredContext = @('UserId')
                parameters      = @(
                    [pscustomobject]@{ name = 'UserId'; contextBinding = 'UserId' }
                )
            }

            $result = Resolve-XdrQueryParameters -Query $query -Context $context

            $result.Success | Should -BeTrue
            $result.IsBlocked | Should -BeFalse
            $result.Parameters['UserId'] | Should -Be '11111111-2222-3333-4444-555555555555'
        }
    }
}