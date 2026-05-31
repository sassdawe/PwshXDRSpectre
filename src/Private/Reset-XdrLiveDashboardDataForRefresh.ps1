function Reset-XdrLiveDashboardDataForRefresh {
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
