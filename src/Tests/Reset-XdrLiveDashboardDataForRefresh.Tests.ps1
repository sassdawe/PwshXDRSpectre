BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Reset-XdrLiveDashboardDataForRefresh' {
    It 'captures incident, alert, and entity selection when preserving refresh state' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1' -Mode 'live'
            $selectedIncident = [pscustomobject]@{ IncidentId = 'inc-2' }
            $selectedAlert = [pscustomobject]@{ AlertId = 'alert-2' }
            $selectedEntity = [pscustomobject]@{
                EntityType        = 'User'
                DisplayName       = 'user@contoso.com'
                AlertId           = 'alert-2'
                UserId            = 'user-2'
                UserPrincipalName = 'user@contoso.com'
                Source            = 'AlertEvidence'
            }
            $pendingIncidentId = $null
            $pendingAlertId = $null
            $pendingEntityKey = $null
            $dataLoaded = $true
            $incidentLoadJob = $null
            $visibleAlerts = @([pscustomobject]@{ AlertId = 'alert-2' })
            $visibleAlertIncidentId = 'inc-2'
            $selectedIndex = 4
            $selectedAlertIndex = 1
            $selectedEntityIndex = 2
            $selectedIncidentRef = $selectedIncident
            $selectedAlertRef = $selectedAlert
            $selectedEntityRef = $selectedEntity

            Reset-XdrLiveDashboardDataForRefresh -Context $context -ReasonMessage 'refresh' -PreserveSelection $true -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -SelectedEntity $selectedEntity -PendingRefreshIncidentId ([ref]$pendingIncidentId) -PendingRefreshAlertId ([ref]$pendingAlertId) -PendingRefreshEntityKey ([ref]$pendingEntityKey) -DataLoaded ([ref]$dataLoaded) -IncidentLoadJob ([ref]$incidentLoadJob) -AlertLoadJobsByIncidentId @{} -EntityLoadJobsByIncidentId @{} -AlertPreloadQueue ([System.Collections.Queue]::new()) -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -SelectedIndex ([ref]$selectedIndex) -SelectedAlertIndex ([ref]$selectedAlertIndex) -SelectedEntityIndex ([ref]$selectedEntityIndex) -SelectedIncidentRef ([ref]$selectedIncidentRef) -SelectedAlertRef ([ref]$selectedAlertRef) -SelectedEntityRef ([ref]$selectedEntityRef) -AlertsByIncidentId @{} -EntitiesByIncidentId @{} -EntityAlertCountByIncidentId @{} -SelectedAlertIdByIncidentId @{}

            $pendingIncidentId | Should -Be 'inc-2'
            $pendingAlertId | Should -Be 'alert-2'
            $pendingEntityKey | Should -Be (Get-XdrEntitySelectionKey -Entity $selectedEntity)
            $selectedIncidentRef.IncidentId | Should -Be 'inc-2'
            $selectedAlertRef.AlertId | Should -Be 'alert-2'
            $selectedEntityRef.DisplayName | Should -Be 'user@contoso.com'
            $selectedIndex | Should -Be 4
            $selectedAlertIndex | Should -Be 1
            $selectedEntityIndex | Should -Be 2
        }
    }
}
