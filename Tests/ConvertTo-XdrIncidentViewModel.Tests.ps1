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
                Classification = 'unknown'
                AssignedTo = 'analyst@contoso.com'
                Determination = 'other'
                CreatedDateTime = [datetime]'2026-04-20T12:00:00Z'
                LastUpdateDateTime = [datetime]'2026-04-21T14:30:00Z'
                SystemTags = @('Important', 'MultiStage')
                CustomTags = @('Case-Blue', 'VIP')
                Alerts = @([pscustomobject]@{ Id = 'alert-1' })
            }

            $vm = ConvertTo-XdrIncidentViewModel -Incident $input -TenantId 'tenant-1'

            $vm.IncidentId | Should -Be 'inc-42'
            $vm.DisplayName | Should -Be 'Test incident'
            $vm.Classification | Should -Be 'unknown'
            $vm.Determination | Should -Be 'other'
            $vm.AlertCount | Should -Be 1
            $vm.LastUpdateDateTime | Should -Be ([datetime]'2026-04-21T14:30:00Z')
            $vm.SystemTags | Should -Be @('Important', 'MultiStage')
            $vm.CustomTags | Should -Be @('Case-Blue', 'VIP')
            $vm.IncidentWebUrl | Should -Be 'https://security.microsoft.com/incident2/inc-42/overview?tid=tenant-1'
            $vm.TenantId | Should -Be 'tenant-1'
            $vm.RawObject.Id | Should -Be 'inc-42'
        }
    }
}
