BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Invoke-XdrLiveActionShortcut' {
    It 'shows warning when load-alert shortcut is used with no selected incident' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{
                Ui = [pscustomobject]@{
                    StatusMessage = ''
                    LastNotification = $null
                }
                Selection = [pscustomobject]@{ Panel = 'incidents' }
            }

            $activePanel = 'incidents'
            $activePanelIndex = 0
            $activePanelBeforeResolution = $null
            $pendingConfirmation = $null
            $pendingTextInput = $null
            $pendingIncidentResolution = $null
            $selectedAlertIndex = 0

            Invoke-XdrLiveActionShortcut -Shortcut 'l' -Context $context -SelectedIncident $null -SelectedAlert $null -TriageOptions ([pscustomobject]@{ IncidentDeterminations = @('TruePositive') }) -PanelOrder @('incidents','incident_details','alerts','alert_details','action_status') -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -ActivePanelBeforeResolution ([ref]$activePanelBeforeResolution) -PendingConfirmation ([ref]$pendingConfirmation) -PendingTextInput ([ref]$pendingTextInput) -PendingIncidentResolution ([ref]$pendingIncidentResolution) -ModulePath 'module.psm1' -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId @{} -SelectedAlertIdByIncidentId @{} -SelectedAlertIndex ([ref]$selectedAlertIndex)

            $context.Ui.StatusMessage | Should -Be 'WARN No incident is selected for loading alerts.'
        }
    }

    It 'syncs visible alert panel state when load-alert shortcut restores cached alerts' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{
                Ui = [pscustomobject]@{
                    StatusMessage = ''
                    LastNotification = $null
                }
                Selection = [pscustomobject]@{ Panel = 'incidents' }
                Data = [pscustomobject]@{ Alerts = @([pscustomobject]@{ AlertId = 'a-1' }) }
            }

            $activePanel = 'incidents'
            $activePanelIndex = 0
            $activePanelBeforeResolution = $null
            $pendingConfirmation = $null
            $pendingTextInput = $null
            $pendingIncidentResolution = $null
            $selectedAlertIndex = 0
            $selectedIncident = [pscustomobject]@{ IncidentId = 'inc-1' }
            $visibleAlerts = @()
            $visibleAlertIncidentId = $null

            Mock Restore-XdrLiveCachedAlertsForIncident { $true }

            Invoke-XdrLiveActionShortcut -Shortcut 'l' -Context $context -SelectedIncident $selectedIncident -SelectedAlert $null -TriageOptions ([pscustomobject]@{ IncidentDeterminations = @('TruePositive') }) -PanelOrder @('incidents','incident_details','alerts','alert_details','action_status') -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -ActivePanelBeforeResolution ([ref]$activePanelBeforeResolution) -PendingConfirmation ([ref]$pendingConfirmation) -PendingTextInput ([ref]$pendingTextInput) -PendingIncidentResolution ([ref]$pendingIncidentResolution) -ModulePath 'module.psm1' -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId @{} -SelectedAlertIdByIncidentId @{} -SelectedAlertIndex ([ref]$selectedAlertIndex) -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId)

            @($visibleAlerts).Count | Should -Be 1
            $visibleAlerts[0].AlertId | Should -Be 'a-1'
            $visibleAlertIncidentId | Should -Be 'inc-1'
        }
    }

    It 'starts a forced reload without consulting cache when reload-alerts shortcut is used' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{
                Ui = [pscustomobject]@{
                    StatusMessage = ''
                    LastNotification = $null
                }
                Selection = [pscustomobject]@{ Panel = 'incidents' }
            }

            $activePanel = 'incidents'
            $activePanelIndex = 0
            $activePanelBeforeResolution = $null
            $pendingConfirmation = $null
            $pendingTextInput = $null
            $pendingIncidentResolution = $null
            $selectedAlertIndex = 0
            $selectedIncident = [pscustomobject]@{ IncidentId = 'inc-1' }

            Mock Restore-XdrLiveCachedAlertsForIncident { throw 'cache should not be consulted' }
            Mock Start-XdrLiveAlertLoadJob { $true }

            Invoke-XdrLiveActionShortcut -Shortcut 'reload-alerts' -Context $context -SelectedIncident $selectedIncident -SelectedAlert $null -TriageOptions ([pscustomobject]@{ IncidentDeterminations = @('TruePositive') }) -PanelOrder @('incidents','incident_details','alerts','alert_details','action_status') -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -ActivePanelBeforeResolution ([ref]$activePanelBeforeResolution) -PendingConfirmation ([ref]$pendingConfirmation) -PendingTextInput ([ref]$pendingTextInput) -PendingIncidentResolution ([ref]$pendingIncidentResolution) -ModulePath 'module.psm1' -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId @{} -SelectedAlertIdByIncidentId @{} -SelectedAlertIndex ([ref]$selectedAlertIndex)

            $context.Ui.StatusMessage | Should -Be 'INFO Force reloading alerts in background...'
            Should -Invoke Restore-XdrLiveCachedAlertsForIncident -Times 0
            Should -Invoke Start-XdrLiveAlertLoadJob -Times 1 -ParameterFilter { $ForceReload -and $RestoreSelectionOnCompletion }
        }
    }
}