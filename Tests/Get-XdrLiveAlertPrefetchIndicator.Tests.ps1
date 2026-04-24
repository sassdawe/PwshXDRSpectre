BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrLiveAlertPrefetchIndicator' {
    It 'returns progress line while prefetch is in progress' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{
                Data = [pscustomobject]@{
                    Incidents = @(
                        [pscustomobject]@{ IncidentId = 'inc-1' },
                        [pscustomobject]@{ IncidentId = 'inc-2' }
                    )
                }
            }
            $cache = @{ 'inc-1' = @() }
            $jobs = @{}
            $queue = [System.Collections.Queue]::new()
            $prefetchCompletedAt = $null

            $line = Get-XdrLiveAlertPrefetchIndicator -Context $context -AlertsByIncidentId $cache -AlertLoadJobsByIncidentId $jobs -AlertPreloadQueue $queue -PrefetchCompletedAt ([ref]$prefetchCompletedAt)

            $line | Should -Match '^prefetch 1/2 '
        }
    }
}