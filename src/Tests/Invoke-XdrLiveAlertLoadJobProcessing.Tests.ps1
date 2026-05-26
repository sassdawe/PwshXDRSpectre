BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Invoke-XdrLiveAlertLoadJobProcessing' {
    It 'stores loaded alerts and clears completed job entry' {
        InModuleScope PwshXDRSpectre {
            $job = Start-Job -ScriptBlock {
                [pscustomobject]@{
                    IncidentId                   = 'inc-1'
                    RestoreSelectionOnCompletion = $true
                    Result                       = [pscustomobject]@{
                        Success = $true
                        Data    = @([pscustomobject]@{ AlertId = 'a-1' })
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
            $visibleAlerts = @()
            $visibleAlertIncidentId = $null

            Mock Restore-XdrLiveCachedAlertsForIncident { $true }
            $context.Data | Add-Member -MemberType NoteProperty -Name Alerts -Value @([pscustomobject]@{ AlertId = 'a-1' }) -Force

            Invoke-XdrLiveAlertLoadJobProcessing -AlertLoadJobsByIncidentId $jobs -AlertsByIncidentId $cache -SelectedIncident $selectedIncident -Context $context -SelectedAlertIdByIncidentId $selectedMap -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex) -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId)

            $jobs.ContainsKey('inc-1') | Should -BeFalse
            $cache.ContainsKey('inc-1') | Should -BeTrue
            Should -Invoke Restore-XdrLiveCachedAlertsForIncident -Times 1
            @($visibleAlerts).Count | Should -Be 1
            $visibleAlertIncidentId | Should -Be 'inc-1'

        }
    }

    It 'updates the visible alerts panel when prefetch completes for the selected incident' {
        InModuleScope PwshXDRSpectre {
            $job = Start-Job -ScriptBlock {
                [pscustomobject]@{
                    IncidentId                   = 'inc-1'
                    RestoreSelectionOnCompletion = $false
                    Result                       = [pscustomobject]@{
                        Success = $true
                        Data    = @([pscustomobject]@{ AlertId = 'a-2' })
                    }
                }
            }
            Wait-Job -Job $job | Out-Null

            $jobs = @{ 'inc-1' = $job }
            $cache = @{}
            $selectedIncident = [pscustomobject]@{ IncidentId = 'inc-1' }
            $context = [pscustomobject]@{ Data = [pscustomobject]@{ Alerts = @([pscustomobject]@{ AlertId = 'existing' }) }; Selection = [pscustomobject]@{} }
            $selectedMap = @{}
            $selectedAlert = $null
            $selectedAlertIndex = 0
            $visibleAlerts = @([pscustomobject]@{ AlertId = 'existing' })
            $visibleAlertIncidentId = 'inc-other'

            Mock Restore-XdrLiveCachedAlertsForIncident {
                $Context.Data.Alerts = @($AlertsByIncidentId[$IncidentId])
                $SelectedAlert.Value = $Context.Data.Alerts[0]
                $SelectedAlertIndex.Value = 0
                $true
            }

            Invoke-XdrLiveAlertLoadJobProcessing -AlertLoadJobsByIncidentId $jobs -AlertsByIncidentId $cache -SelectedIncident $selectedIncident -Context $context -SelectedAlertIdByIncidentId $selectedMap -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex) -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId)

            $jobs.ContainsKey('inc-1') | Should -BeFalse
            $cache.ContainsKey('inc-1') | Should -BeTrue
            @($context.Data.Alerts).Count | Should -Be 1
            $context.Data.Alerts[0].AlertId | Should -Be 'a-2'
            @($visibleAlerts).Count | Should -Be 1
            $visibleAlerts[0].AlertId | Should -Be 'a-2'
            $visibleAlertIncidentId | Should -Be 'inc-1'
            Should -Invoke Restore-XdrLiveCachedAlertsForIncident -Times 1
        }
    }

    It 'does not update the visible alerts panel when prefetch completes for another incident' {
        InModuleScope PwshXDRSpectre {
            $job = Start-Job -ScriptBlock {
                [pscustomobject]@{
                    IncidentId                   = 'inc-2'
                    RestoreSelectionOnCompletion = $false
                    Result                       = [pscustomobject]@{
                        Success = $true
                        Data    = @([pscustomobject]@{ AlertId = 'a-2' })
                    }
                }
            }
            Wait-Job -Job $job | Out-Null

            $jobs = @{ 'inc-2' = $job }
            $cache = @{}
            $selectedIncident = [pscustomobject]@{ IncidentId = 'inc-1' }
            $context = [pscustomobject]@{ Data = [pscustomobject]@{ Alerts = @([pscustomobject]@{ AlertId = 'existing' }) }; Selection = [pscustomobject]@{} }
            $selectedMap = @{}
            $selectedAlert = $null
            $selectedAlertIndex = 0
            $visibleAlerts = @([pscustomobject]@{ AlertId = 'existing' })
            $visibleAlertIncidentId = 'inc-1'

            Mock Restore-XdrLiveCachedAlertsForIncident { $true }

            Invoke-XdrLiveAlertLoadJobProcessing -AlertLoadJobsByIncidentId $jobs -AlertsByIncidentId $cache -SelectedIncident $selectedIncident -Context $context -SelectedAlertIdByIncidentId $selectedMap -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex) -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId)

            $jobs.ContainsKey('inc-2') | Should -BeFalse
            $cache.ContainsKey('inc-2') | Should -BeTrue
            @($context.Data.Alerts).Count | Should -Be 1
            $context.Data.Alerts[0].AlertId | Should -Be 'existing'
            @($visibleAlerts).Count | Should -Be 1
            $visibleAlerts[0].AlertId | Should -Be 'existing'
            $visibleAlertIncidentId | Should -Be 'inc-1'
            Should -Invoke Restore-XdrLiveCachedAlertsForIncident -Times 0
        }
    }
}