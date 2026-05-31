BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrIncidents' {
    It 'loads incidents without expanding alerts eagerly' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1' -Mode 'live'

            Mock Get-MgSecurityIncident {
                [pscustomobject]@{
                    Id = 'inc-1'
                    DisplayName = 'Incident one'
                    Status = 'active'
                    Severity = 'medium'
                }
            }

            $result = Get-XdrIncidents -Context $context -Limit 1

            $result.Success | Should -BeTrue
            @($result.Data).Count | Should -Be 1
            Should -Invoke Get-MgSecurityIncident -Times 1 -Exactly -ParameterFilter {
                -not $PSBoundParameters.ContainsKey('ExpandProperty')
            }
        }
    }

    Context 'comment-based help' {
        It 'has a Synopsis' {
            (Get-Help Get-XdrIncidents).Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'has a Description' {
            (Get-Help Get-XdrIncidents).Description | Should -Not -BeNullOrEmpty
        }
    }
}