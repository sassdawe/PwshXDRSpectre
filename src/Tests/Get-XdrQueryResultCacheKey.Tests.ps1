BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrQueryResultCacheKey' {
    It 'builds a stable key from query id and sorted context snapshot values' {
        InModuleScope PwshXDRSpectre {
            $key = Get-XdrQueryResultCacheKey -QueryId 'query-1' -ContextSnapshot ([pscustomobject]@{ UserId = 'user-1'; IncidentId = '40' })

            $key | Should -Be 'query-1|IncidentId=40;UserId=user-1'
        }
    }

    It 'returns a query-only key when no context snapshot is provided' {
        InModuleScope PwshXDRSpectre {
            $key = Get-XdrQueryResultCacheKey -QueryId 'query-1'

            $key | Should -Be 'query-1|'
        }
    }
}