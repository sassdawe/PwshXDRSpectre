BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Start-XdrLiveQueuedAlertPreloads' {
    It 'dequeues and starts jobs up to max concurrency' {
        InModuleScope PwshXDRSpectre {
            $jobs = @{}
            $queue = [System.Collections.Queue]::new()
            $queue.Enqueue([pscustomobject]@{ IncidentId = 'inc-1' })
            $queue.Enqueue([pscustomobject]@{ IncidentId = 'inc-2' })

            Mock Start-XdrLiveAlertLoadJob {
                $AlertLoadJobsByIncidentId[[string]$Incident.IncidentId] = [pscustomobject]@{ State = 'Running' }
                $true
            }

            Start-XdrLiveQueuedAlertPreloads -AlertLoadJobsByIncidentId $jobs -MaxAlertLoadJobs 1 -AlertPreloadQueue $queue -ModulePath 'module.psm1' -Context ([pscustomobject]@{}) -AlertsByIncidentId @{}

            $jobs.Count | Should -Be 1
            $queue.Count | Should -Be 1
        }
    }
}