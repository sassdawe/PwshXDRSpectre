BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Invoke-XdrLiveQueryJobProcessing' {
    It 'applies successful query results and appends query history' {
        InModuleScope PwshXDRSpectre {
            $job = Start-Job -ScriptBlock {
                [pscustomobject]@{
                    QueryId = 'query-1'
                    Result  = [pscustomobject]@{
                        Success = $true
                        Message = 'ok'
                        Data    = [pscustomobject]@{
                            QueryId  = 'query-1'
                            RowCount = 1
                            Results  = @([pscustomobject]@{ Name = 'row-1' })
                            QueryRun = [pscustomobject]@{ QueryId = 'query-1'; Status = 'Success' }
                        }
                    }
                }
            }
            Wait-Job -Job $job | Out-Null

            $queryJob = $job
            $queryResultsByQueryId = @{}
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $selectedQuery = [pscustomobject]@{ id = 'query-1' }
            $selectedQueryResult = $null

            Mock Set-StatusFromResult {}

            Invoke-XdrLiveQueryJobProcessing -QueryJob ([ref]$queryJob) -QueryResultsByQueryId $queryResultsByQueryId -Context $context -SelectedQuery $selectedQuery -SelectedQueryResult ([ref]$selectedQueryResult)

            $queryJob | Should -BeNullOrEmpty
            $selectedQueryResult.RowCount | Should -Be 1
            $queryResultsByQueryId['query-1'].RowCount | Should -Be 1
            $context.Data.QueryRuns.Count | Should -Be 1
            $context.Data.QueryRuns[0].QueryId | Should -Be 'query-1'
            Should -Invoke Set-StatusFromResult -Times 1
        }
    }

    It 'does not overwrite visible results when a different query completes' {
        InModuleScope PwshXDRSpectre {
            $job = Start-Job -ScriptBlock {
                [pscustomobject]@{
                    QueryId = 'query-1'
                    Result  = [pscustomobject]@{
                        Success = $true
                        Message = 'ok'
                        Data    = [pscustomobject]@{
                            QueryId  = 'query-1'
                            RowCount = 1
                            Results  = @([pscustomobject]@{ Name = 'row-1' })
                            QueryRun = [pscustomobject]@{ QueryId = 'query-1'; Status = 'Success' }
                        }
                    }
                }
            }
            Wait-Job -Job $job | Out-Null

            $queryJob = $job
            $queryResultsByQueryId = @{}
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $selectedQuery = [pscustomobject]@{ id = 'query-2' }
            $selectedQueryResult = [pscustomobject]@{ RowCount = 99 }

            Mock Set-StatusFromResult {}

            Invoke-XdrLiveQueryJobProcessing -QueryJob ([ref]$queryJob) -QueryResultsByQueryId $queryResultsByQueryId -Context $context -SelectedQuery $selectedQuery -SelectedQueryResult ([ref]$selectedQueryResult)

            $selectedQueryResult.RowCount | Should -Be 99
            $queryResultsByQueryId['query-1'].RowCount | Should -Be 1
            $context.Data.QueryRuns.Count | Should -Be 1
            Should -Invoke Set-StatusFromResult -Times 1
        }
    }
}