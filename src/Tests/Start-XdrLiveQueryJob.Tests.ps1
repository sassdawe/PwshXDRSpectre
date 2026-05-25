BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
    $script:queryJobPath = Join-Path $PSScriptRoot '..' 'Private' 'Start-XdrLiveQueryJob.ps1'
}

Describe 'Start-XdrLiveQueryJob' {
    It 'returns null when query id is missing' {
        InModuleScope PwshXDRSpectre {
            $result = Start-XdrLiveQueryJob -Query ([pscustomobject]@{ id = '' }) -ModulePath 'module.psm1' -Context (New-XdrRuntimeContext)

            $result | Should -BeNullOrEmpty
        }
    }

    It 'starts a thread job for a valid query' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Selection.Entity = [pscustomobject]@{ UserId = 'user-1' }

            Mock Start-ThreadJob { [pscustomobject]@{ Id = 100; State = 'Running' } }

            $job = Start-XdrLiveQueryJob -Query ([pscustomobject]@{ id = 'query-1'; name = 'Query 1' }) -ModulePath 'module.psm1' -Context $context

            $job.Id | Should -Be 100
        }
    }

    It 'passes an isolated runtime context snapshot with current selection to thread jobs' {
        InModuleScope PwshXDRSpectre {
            $capturedContext = $null
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1' -Mode 'live' -ThemeColor 'Orange1'
            $context.Session.Analyst = 'analyst@example.com'
            $context.Selection.Incident = [pscustomobject]@{ IncidentId = 'inc-1' }
            $context.Selection.Entity = [pscustomobject]@{ UserId = 'user-1' }

            Mock Start-ThreadJob {
                $script:capturedContext = $ArgumentList[1]
                [pscustomobject]@{ Id = 100; State = 'Running' }
            }

            $null = Start-XdrLiveQueryJob -Query ([pscustomobject]@{ id = 'query-1'; name = 'Query 1' }) -ModulePath 'module.psm1' -Context $context

            [object]::ReferenceEquals($script:capturedContext, $context) | Should -BeFalse
            $script:capturedContext.Selection.Incident.IncidentId | Should -Be 'inc-1'
            $script:capturedContext.Selection.Entity.UserId | Should -Be 'user-1'
            $script:capturedContext.Session.Analyst | Should -Be 'analyst@example.com'
        }
    }

    It 'logs from query thread jobs through module scope' {
        $content = Get-Content -Path $script:queryJobPath -Raw

        $content.Contains('& (Get-Module PwshXDRSpectre) {') | Should -BeTrue
        $content.Contains('Write-XdrLiveDashboardLog -LogPath $InnerJobLogPath -Message "Hunting query job started. QueryId=$InnerJobQueryId"') | Should -BeTrue
        $content.Contains('Write-XdrLiveDashboardLog -LogPath $InnerJobLogPath -Message "Hunting query job completed. QueryId=$InnerJobQueryId Result=$InnerResultStatus"') | Should -BeTrue
    }
}