BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'New-XdrRuntimeContext' {
    It 'returns expected default structure' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'

            $context.Session.TenantId | Should -Be 'tenant-1'
            $context.Session.ClientId | Should -Be 'client-1'
            $context.Session.IsConnected | Should -BeFalse
            $context.Session.PermissionHealth.HasSufficientWritePermissions | Should -BeTrue
            $context.Session.PermissionHealth.DetectionSource | Should -Be 'default'
            $context.Ui.Mode | Should -Be 'menu'
            $context.Data.Incidents.GetType().FullName | Should -Be 'System.Object[]'
            $context.Diagnostics.LastError | Should -BeNullOrEmpty
        }
    }
}
