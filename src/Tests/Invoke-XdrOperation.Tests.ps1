BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Invoke-XdrOperation' {
    It 'returns success envelope for successful script block' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $result = Invoke-XdrOperation -Operation 'UnitTest' -Context $context -ScriptBlock { 'ok' }

            $result.Success | Should -BeTrue
            $result.Data | Should -Be 'ok'
            $context.Diagnostics.LastOperation.Operation | Should -Be 'UnitTest'
            $context.Diagnostics.LastError | Should -BeNullOrEmpty
        }
    }

    It 'returns failure envelope when script block throws' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $result = Invoke-XdrOperation -Operation 'UnitTestFail' -Context $context -ScriptBlock { throw 'boom' }

            $result.Success | Should -BeFalse
            $result.Error.SafeMessage | Should -Be 'Operation failed: UnitTestFail'
            $context.Diagnostics.LastError.Operation | Should -Be 'UnitTestFail'
        }
    }

    It 'captures missing Graph permissions and disables write capabilities' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('AssignIncident', 'UpdateIncidentStatus')
            $context.Capabilities.AlertActions = @('GetAlerts', 'UpdateAlertStatus')

            $permissionError = 'Missing user permissions. API required permissions: SecurityData.Manage, user permissions: SecurityData.Read,SecurityData.Hunting.Read.'

            $result = Invoke-XdrOperation -Operation 'UnitTestPermissionFail' -Context $context -ScriptBlock { throw $permissionError }

            $result.Success | Should -BeFalse
            $context.Session.PermissionHealth.HasSufficientWritePermissions | Should -BeFalse
            $context.Session.PermissionHealth.DetectionSource | Should -Be 'graph-error'
            $context.Session.PermissionHealth.RequiredPermissions | Should -Contain 'SecurityData.Manage'
            $context.Session.PermissionHealth.AvailablePermissions | Should -Contain 'SecurityData.Read'
            $context.Capabilities.IncidentActions.Count | Should -Be 0
            $context.Capabilities.AlertActions | Should -Be @('GetAlerts')
        }
    }
}
