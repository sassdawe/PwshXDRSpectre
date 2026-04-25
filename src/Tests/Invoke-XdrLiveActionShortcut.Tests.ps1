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
}