function Reset-XdrLiveDashboardDataForRefresh {
    <#
    .SYNOPSIS
    Resets live dashboard data before a refresh.

    .DESCRIPTION
    Stops outstanding jobs, clears caches and queued preload work, optionally
    preserves selection identifiers for later rebind, and resets visible state
    needed for a clean refresh.

    .PARAMETER Context
    Runtime context to reset.

    .PARAMETER ReasonMessage
    Optional status message to publish after the reset.

    .PARAMETER PreserveSelection
    Retains selection identifiers so refresh can restore prior selections.

    .PARAMETER SelectedIncident
    Currently selected incident.

    .PARAMETER SelectedAlert
    Currently selected alert.

    .PARAMETER SelectedEntity
    Currently selected entity.

    .PARAMETER PendingRefreshIncidentId
    Reference storing the incident id to restore after refresh.

    .PARAMETER PendingRefreshAlertId
    Reference storing the alert id to restore after refresh.

    .PARAMETER PendingRefreshEntityKey
    Reference storing the entity key to restore after refresh.

    .PARAMETER DataLoaded
    Reference tracking whether incident data is loaded.

    .PARAMETER IncidentLoadJob
    Reference to the active incident load job.

    .PARAMETER AlertLoadJobsByIncidentId
    Running alert jobs keyed by incident id.

    .PARAMETER EntityLoadJobsByIncidentId
    Running entity jobs keyed by incident id.

    .PARAMETER AlertPreloadQueue
    Queue of pending alert preload incidents.

    .PARAMETER VisibleAlerts
    Reference to the alerts currently shown in the dashboard.

    .PARAMETER VisibleAlertIncidentId
    Reference to the incident id backing the visible alerts.

    .PARAMETER SelectedIndex
    Reference to the selected incident index.

    .PARAMETER SelectedAlertIndex
    Reference to the selected alert index.

    .PARAMETER SelectedEntityIndex
    Reference to the selected entity index.

    .PARAMETER SelectedIncidentRef
    Reference to the selected incident object.

    .PARAMETER SelectedAlertRef
    Reference to the selected alert object.

    .PARAMETER SelectedEntityRef
    Reference to the selected entity object.

    .PARAMETER AlertsByIncidentId
    Alert cache keyed by incident id.

    .PARAMETER EntitiesByIncidentId
    Entity cache keyed by incident id.

    .PARAMETER EntityAlertCountByIncidentId
    Entity extraction alert-count cache keyed by incident id.

    .PARAMETER SelectedAlertIdByIncidentId
    Selected alert id cache keyed by incident id.

    .PARAMETER LogPath
    Optional dashboard log path.

    .OUTPUTS
    None

    .EXAMPLE
    Reset-XdrLiveDashboardDataForRefresh -Context $context -PendingRefreshIncidentId ([ref]$pendingRefreshIncidentId) -PendingRefreshAlertId ([ref]$pendingRefreshAlertId) -PendingRefreshEntityKey ([ref]$pendingRefreshEntityKey) -DataLoaded ([ref]$dataLoaded) -IncidentLoadJob ([ref]$incidentLoadJob) -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -EntityLoadJobsByIncidentId $entityLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -SelectedIndex ([ref]$selectedIndex) -SelectedAlertIndex ([ref]$selectedAlertIndex) -SelectedEntityIndex ([ref]$selectedEntityIndex) -SelectedIncidentRef ([ref]$selectedIncident) -SelectedAlertRef ([ref]$selectedAlert) -SelectedEntityRef ([ref]$selectedEntity) -AlertsByIncidentId $alertsByIncidentId -EntitiesByIncidentId $entitiesByIncidentId -EntityAlertCountByIncidentId $entityAlertCountByIncidentId -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter()]
        [string]$ReasonMessage,

        [Parameter()]
        [bool]$PreserveSelection = $true,

        [Parameter()]
        [object]$SelectedIncident,

        [Parameter()]
        [object]$SelectedAlert,

        [Parameter()]
        [object]$SelectedEntity,

        [Parameter(Mandatory)]
        [ref]$PendingRefreshIncidentId,

        [Parameter(Mandatory)]
        [ref]$PendingRefreshAlertId,

        [Parameter(Mandatory)]
        [ref]$PendingRefreshEntityKey,

        [Parameter(Mandatory)]
        [ref]$DataLoaded,

        [Parameter(Mandatory)]
        [ref]$IncidentLoadJob,

        [Parameter(Mandatory)]
        [hashtable]$AlertLoadJobsByIncidentId,

        [Parameter(Mandatory)]
        [hashtable]$EntityLoadJobsByIncidentId,

        [Parameter(Mandatory)]
        [System.Collections.Queue]$AlertPreloadQueue,

        [Parameter(Mandatory)]
        [ref]$VisibleAlerts,

        [Parameter(Mandatory)]
        [ref]$VisibleAlertIncidentId,

        [Parameter(Mandatory)]
        [ref]$SelectedIndex,

        [Parameter(Mandatory)]
        [ref]$SelectedAlertIndex,

        [Parameter(Mandatory)]
        [ref]$SelectedEntityIndex,

        [Parameter(Mandatory)]
        [ref]$SelectedIncidentRef,

        [Parameter(Mandatory)]
        [ref]$SelectedAlertRef,

        [Parameter(Mandatory)]
        [ref]$SelectedEntityRef,

        [Parameter(Mandatory)]
        [hashtable]$AlertsByIncidentId,

        [Parameter(Mandatory)]
        [hashtable]$EntitiesByIncidentId,

        [Parameter(Mandatory)]
        [hashtable]$EntityAlertCountByIncidentId,

        [Parameter(Mandatory)]
        [hashtable]$SelectedAlertIdByIncidentId,

        [Parameter()]
        [string]$LogPath
    )

    $PendingRefreshIncidentId.Value = if ($PreserveSelection -and $SelectedIncident) { [string]$SelectedIncident.IncidentId } else { $null }
    $PendingRefreshAlertId.Value = if ($PreserveSelection -and $SelectedAlert) { [string]$SelectedAlert.AlertId } else { $null }
    $PendingRefreshEntityKey.Value = if ($PreserveSelection -and $SelectedEntity) { Get-XdrEntitySelectionKey -Entity $SelectedEntity } else { $null }

    Write-XdrLiveDashboardLog -LogPath $LogPath -Message "Resetting dashboard data for refresh. PreserveSelection=$PreserveSelection IncidentId=$($PendingRefreshIncidentId.Value) AlertId=$($PendingRefreshAlertId.Value) EntityKey=$($PendingRefreshEntityKey.Value)"

    $DataLoaded.Value = $false
    if ($IncidentLoadJob.Value -and $IncidentLoadJob.Value.State -notin @('Completed', 'Failed', 'Stopped')) {
        Stop-Job -Job $IncidentLoadJob.Value -ErrorAction SilentlyContinue | Out-Null
    }
    if ($IncidentLoadJob.Value) {
        Remove-Job -Job $IncidentLoadJob.Value -Force -ErrorAction SilentlyContinue
        $IncidentLoadJob.Value = $null
    }

    foreach ($jobEntry in @($AlertLoadJobsByIncidentId.GetEnumerator())) {
        Stop-Job -Job $jobEntry.Value -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $jobEntry.Value -Force -ErrorAction SilentlyContinue
    }
    foreach ($entityJobEntry in @($EntityLoadJobsByIncidentId.GetEnumerator())) {
        Stop-Job -Job $entityJobEntry.Value -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $entityJobEntry.Value -Force -ErrorAction SilentlyContinue
    }

    $AlertLoadJobsByIncidentId.Clear()
    $EntityLoadJobsByIncidentId.Clear()
    $AlertPreloadQueue.Clear()

    if (-not $PreserveSelection) {
        $Context.Data.Incidents = @()
        $Context.Data.Alerts = @()
        $Context.Data.Entities = @()
        $VisibleAlerts.Value = @()
        $VisibleAlertIncidentId.Value = $null
        $SelectedIndex.Value = 0
        $SelectedAlertIndex.Value = 0
        $SelectedEntityIndex.Value = 0
        $SelectedIncidentRef.Value = $null
        $SelectedAlertRef.Value = $null
        $SelectedEntityRef.Value = $null
        $Context.Selection.Incident = $null
        $Context.Selection.Alert = $null
        $Context.Selection.Entity = $null
        $AlertsByIncidentId.Clear()
        $EntitiesByIncidentId.Clear()
        $EntityAlertCountByIncidentId.Clear()
        $SelectedAlertIdByIncidentId.Clear()
    }

    if (-not [string]::IsNullOrWhiteSpace($ReasonMessage)) {
        Set-LiveStatusMessage -Context $Context -Message $ReasonMessage -Level 'info'
    }

    Write-XdrLiveDashboardLog -LogPath $LogPath -Message 'Dashboard data reset completed.'
}
