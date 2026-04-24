BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Restore-XdrLiveCachedAlertsForIncident' {
    It 'restores cached alerts and selected alert reference' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{
                Data = [pscustomobject]@{ Alerts = @() }
                Selection = [pscustomobject]@{ Alert = $null }
            }
            $alertsByIncidentId = @{
                'inc-1' = @(
                    [pscustomobject]@{ AlertId = 'a-1' },
                    [pscustomobject]@{ AlertId = 'a-2' }
                )
            }
            $selectedMap = @{ 'inc-1' = 'a-2' }
            $selectedAlert = $null
            $selectedAlertIndex = 0

            $result = Restore-XdrLiveCachedAlertsForIncident -IncidentId 'inc-1' -AlertsByIncidentId $alertsByIncidentId -Context $context -SelectedAlertIdByIncidentId $selectedMap -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex)

            $result | Should -BeTrue
            $selectedAlertIndex | Should -Be 1
            $selectedAlert.AlertId | Should -Be 'a-2'
        }
    }
}