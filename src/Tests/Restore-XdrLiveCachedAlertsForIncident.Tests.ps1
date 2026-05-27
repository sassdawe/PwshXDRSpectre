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

    It 'writes cache restore diagnostics when a log path is provided' {
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
            $logPath = Join-Path $TestDrive 'restore-cache.log'

            Restore-XdrLiveCachedAlertsForIncident -IncidentId 'inc-1' -AlertsByIncidentId $alertsByIncidentId -Context $context -SelectedAlertIdByIncidentId $selectedMap -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex) -LogPath $logPath | Should -BeTrue

            $logContent = Get-Content -Path $logPath -Raw
            $logContent | Should -Match 'Alert cache restore hit\. IncidentId=inc-1 AlertCount=2'
            $logContent | Should -Match 'Attempting cached alert selection restore\. IncidentId=inc-1 CachedAlertId=a-2'
            $logContent | Should -Match 'Alert cache restore selected alert\. IncidentId=inc-1 SelectedAlertId=a-2 SelectedAlertIndex=1'
        }
    }

    It 'logs cache misses when the incident has no cached alerts' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{
                Data = [pscustomobject]@{ Alerts = @() }
                Selection = [pscustomobject]@{ Alert = $null }
            }
            $selectedAlert = $null
            $selectedAlertIndex = 0
            $logPath = Join-Path $TestDrive 'restore-miss.log'

            Restore-XdrLiveCachedAlertsForIncident -IncidentId 'inc-missing' -AlertsByIncidentId @{} -Context $context -SelectedAlertIdByIncidentId @{} -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex) -LogPath $logPath | Should -BeFalse

            Get-Content -Path $logPath -Raw | Should -Match 'Alert cache restore miss\. IncidentId=inc-missing CacheIncidentCount=0'
        }
    }
}