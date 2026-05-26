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
                            QueryId         = 'query-1'
                            RowCount        = 1
                            Results         = @([pscustomobject]@{ Name = 'row-1' })
                            ContextSnapshot = [pscustomobject]@{ DeviceId = 'device-123' }
                            QueryRun        = [pscustomobject]@{ QueryId = 'query-1'; Status = 'Success' }
                        }
                    }
                }
            }
            Wait-Job -Job $job | Out-Null

            $queryJob = $job
            $queryResultsByCacheKey = @{}
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Selection.Entity = [pscustomobject]@{ DeviceId = 'device-123' }
            $selectedQuery = [pscustomobject]@{ id = 'query-1' }
            $selectedQueryResult = $null

            Mock Set-StatusFromResult {}
            Mock Resolve-XdrQueryParameters {
                [pscustomobject]@{
                    IsBlocked  = $false
                    Parameters = [ordered]@{ DeviceId = 'device-123' }
                }
            }

            Invoke-XdrLiveQueryJobProcessing -QueryJob ([ref]$queryJob) -QueryResultsByCacheKey $queryResultsByCacheKey -Context $context -SelectedQuery $selectedQuery -SelectedQueryResult ([ref]$selectedQueryResult)

            $queryJob | Should -BeNullOrEmpty
            $selectedQueryResult.RowCount | Should -Be 1
            $queryResultsByCacheKey['query-1|DeviceId=device-123'].RowCount | Should -Be 1
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
                            QueryId         = 'query-1'
                            RowCount        = 1
                            Results         = @([pscustomobject]@{ Name = 'row-1' })
                            ContextSnapshot = [pscustomobject]@{}
                            QueryRun        = [pscustomobject]@{ QueryId = 'query-1'; Status = 'Success' }
                        }
                    }
                }
            }
            Wait-Job -Job $job | Out-Null

            $queryJob = $job
            $queryResultsByCacheKey = @{}
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Selection.Entity = [pscustomobject]@{ DeviceId = 'device-999' }
            $selectedQuery = [pscustomobject]@{ id = 'query-2' }
            $selectedQueryResult = [pscustomobject]@{ RowCount = 99 }

            Mock Set-StatusFromResult {}
            Mock Resolve-XdrQueryParameters {
                [pscustomobject]@{
                    IsBlocked  = $false
                    Parameters = [ordered]@{ DeviceId = 'device-999' }
                }
            }

            Invoke-XdrLiveQueryJobProcessing -QueryJob ([ref]$queryJob) -QueryResultsByCacheKey $queryResultsByCacheKey -Context $context -SelectedQuery $selectedQuery -SelectedQueryResult ([ref]$selectedQueryResult)

            $selectedQueryResult.RowCount | Should -Be 99
            $queryResultsByCacheKey['query-1|'].RowCount | Should -Be 1
            $context.Data.QueryRuns.Count | Should -Be 1
            Should -Invoke Set-StatusFromResult -Times 1
        }
    }
}