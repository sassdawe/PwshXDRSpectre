BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Invoke-XdrLiveAlertLoadJobProcessing' {
    It 'stores loaded alerts and clears completed job entry' {
        InModuleScope PwshXDRSpectre {
            $job = Start-Job -ScriptBlock {
                [pscustomobject]@{
                    IncidentId = 'inc-1'
                    Result = [pscustomobject]@{
                        Success = $true
                        Data = @([pscustomobject]@{ AlertId = 'a-1' })
                    }
                }
            }
            Wait-Job -Job $job | Out-Null

            $jobs = @{ 'inc-1' = $job }
            $cache = @{}
            $selectedIncident = [pscustomobject]@{ IncidentId = 'inc-1' }
            $context = [pscustomobject]@{ Data = [pscustomobject]@{}; Selection = [pscustomobject]@{} }
            $selectedMap = @{}
            $selectedAlert = $null
            $selectedAlertIndex = 0

            Mock Restore-XdrLiveCachedAlertsForIncident { $true }

            Invoke-XdrLiveAlertLoadJobProcessing -AlertLoadJobsByIncidentId $jobs -AlertsByIncidentId $cache -SelectedIncident $selectedIncident -Context $context -SelectedAlertIdByIncidentId $selectedMap -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex)

            $jobs.ContainsKey('inc-1') | Should -BeFalse
            $cache.ContainsKey('inc-1') | Should -BeTrue
            Should -Invoke Restore-XdrLiveCachedAlertsForIncident -Times 1

        }
    }
}