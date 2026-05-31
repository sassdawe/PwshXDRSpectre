BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'ConvertTo-XdrAlertViewModel' {
    It 'maps important alert fields' {
        InModuleScope PwshXDRSpectre {
            $input = [pscustomobject]@{
                Id = 'alert-88'
                Title = 'Suspicious activity'
                Status = 'new'
                Severity = 'medium'
                CreatedDateTime = [datetime]'2026-04-20T12:01:00Z'
                AlertWebUrl = 'https://security.microsoft.com/alert'
                Evidence = @([pscustomobject]@{ EntityType = 'Device'; DeviceName = 'device-01' })
                Entities = @([pscustomobject]@{ EntityType = 'User'; UserPrincipalName = 'analyst@example.com' })
            }

            $vm = ConvertTo-XdrAlertViewModel -Alert $input -IncidentId 'inc-42'

            $vm.AlertId | Should -Be 'alert-88'
            $vm.IncidentId | Should -Be 'inc-42'
            $vm.Title | Should -Be 'Suspicious activity'
            $vm.AlertWebUrl | Should -Be 'https://security.microsoft.com/alert'
            @($vm.Evidence).Count | Should -Be 1
            @($vm.Entities).Count | Should -Be 1
            $vm.PSObject.Properties.Name | Should -Not -Contain 'RawObject'
        }
    }
}
