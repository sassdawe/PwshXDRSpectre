BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'ConvertTo-XdrIncidentViewModel' {
    It 'maps important incident fields' {
        InModuleScope PwshXDRSpectre {
            $input = [pscustomobject]@{
                Id = 'inc-42'
                DisplayName = 'Test incident'
                Status = 'active'
                Severity = 'high'
                AssignedTo = 'analyst@contoso.com'
                Determination = 'unknown'
                CreatedDateTime = [datetime]'2026-04-20T12:00:00Z'
                Alerts = @([pscustomobject]@{ Id = 'alert-1' })
            }

            $vm = ConvertTo-XdrIncidentViewModel -Incident $input -TenantId 'tenant-1'

            $vm.IncidentId | Should -Be 'inc-42'
            $vm.DisplayName | Should -Be 'Test incident'
            $vm.AlertCount | Should -Be 1
            $vm.IncidentWebUrl | Should -Be 'https://security.microsoft.com/incident2/inc-42/overview?tid=tenant-1'
            $vm.TenantId | Should -Be 'tenant-1'
            $vm.RawObject.Id | Should -Be 'inc-42'
        }
    }
}
