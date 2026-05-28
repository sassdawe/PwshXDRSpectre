BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrEntitySelectionKey' {
    It 'builds a stable key from entity identity fields' {
        InModuleScope PwshXDRSpectre {
            $entity = [pscustomobject]@{
                EntityType        = 'User'
                DisplayName       = 'analyst@contoso.com'
                AlertId           = 'alert-1'
                UserId            = 'user-1'
                UserPrincipalName = 'analyst@contoso.com'
                DeviceId          = ''
                Sha256            = ''
                Source            = 'AlertEvidence'
            }

            Get-XdrEntitySelectionKey -Entity $entity | Should -Be 'User|analyst@contoso.com|alert-1|user-1|analyst@contoso.com|||AlertEvidence'
        }
    }

    It 'returns an empty key for a missing entity' {
        InModuleScope PwshXDRSpectre {
            Get-XdrEntitySelectionKey -Entity $null | Should -Be ''
        }
    }
}
