BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Add-XdrLiveAlertPreloads' {
    It 'queues only incidents that are neither cached nor loading' {
        InModuleScope PwshXDRSpectre {
            $incidents = @(
                [pscustomobject]@{ IncidentId = 'inc-1' },
                [pscustomobject]@{ IncidentId = 'inc-2' },
                [pscustomobject]@{ IncidentId = 'inc-3' }
            )
            $queue = [System.Collections.Queue]::new()
            $cache = @{ 'inc-1' = @() }
            $jobs = @{ 'inc-2' = [pscustomobject]@{ State = 'Running' } }

            Add-XdrLiveAlertPreloads -Incidents $incidents -AlertPreloadQueue $queue -AlertsByIncidentId $cache -AlertLoadJobsByIncidentId $jobs

            $queue.Count | Should -Be 1
            $queue.Peek().IncidentId | Should -Be 'inc-3'
        }
    }
}