BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrAssignTargetIdentity' {
    It 'prefers mail over user principal name for assign target identity' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Session.Analyst = [pscustomobject]@{
                Mail = 'analyst@contoso.com'
                UserPrincipalName = 'analyst-upn@contoso.com'
            }

            Get-XdrAssignTargetIdentity -Context $context | Should -Be 'analyst@contoso.com'
        }
    }

    It 'falls back to user principal name when mail is empty' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Session.Analyst = [pscustomobject]@{
                Mail = ''
                UserPrincipalName = 'analyst-upn@contoso.com'
            }

            Get-XdrAssignTargetIdentity -Context $context | Should -Be 'analyst-upn@contoso.com'
        }
    }
}