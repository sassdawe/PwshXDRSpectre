BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Add-XdrQueryRun' {
    It 'appends a query run record with all required fields populated' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'

            $queryRun = Add-XdrQueryRun -Context $context -QueryId 'user-signin-anomalies' -QueryName 'User Sign-In Anomalies' -ContextSnapshot ([ordered]@{ UserId = '11111111-2222-3333-4444-555555555555' }) -DurationMs 125 -Status 'Success' -RowCount 3

            $context.Data.QueryRuns.Count | Should -Be 1
            $queryRun.QueryId | Should -Be 'user-signin-anomalies'
            $queryRun.QueryName | Should -Be 'User Sign-In Anomalies'
            $queryRun.Status | Should -Be 'Success'
            $queryRun.RowCount | Should -Be 3
            $queryRun.DurationMs | Should -Be 125
            $queryRun.ContextSnapshot.UserId | Should -Be '11111111-2222-3333-4444-555555555555'
            { [guid]$queryRun.RunId } | Should -Not -Throw
        }
    }
}