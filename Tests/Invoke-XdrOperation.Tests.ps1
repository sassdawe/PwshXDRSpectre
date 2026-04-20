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
}
