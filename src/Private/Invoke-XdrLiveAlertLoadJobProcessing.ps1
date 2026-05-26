function Invoke-XdrLiveAlertLoadJobProcessing {
    <#
    .SYNOPSIS
    Processes completed alert load jobs.

    .DESCRIPTION
    Receives completed background job output, updates the alert cache, and
    refreshes the visible alert panel when the loaded incident is selected.

    .PARAMETER AlertLoadJobsByIncidentId
    Running jobs map keyed by incident id.

    .PARAMETER AlertsByIncidentId
    Alert cache map keyed by incident id.

    .PARAMETER SelectedIncident
    Currently selected incident.

    .PARAMETER Context
    Runtime context object.

    .PARAMETER SelectedAlertIdByIncidentId
    Last selected alert id map keyed by incident id.

    .PARAMETER SelectedAlert
    Selected alert reference.

    .PARAMETER SelectedAlertIndex
    Selected alert index reference.

    .PARAMETER VisibleAlerts
    Alert collection currently shown in the dashboard alert panel.

    .PARAMETER VisibleAlertIncidentId
    Incident id associated with the current visible alert panel.

    .OUTPUTS
    None

    .EXAMPLE
    Invoke-XdrLiveAlertLoadJobProcessing -AlertLoadJobsByIncidentId $jobs -AlertsByIncidentId $cache -SelectedIncident $selectedIncident -Context $context -SelectedAlertIdByIncidentId $selectedMap -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AlertLoadJobsByIncidentId,

        [Parameter(Mandatory)]
        [hashtable]$AlertsByIncidentId,

        [Parameter()]
        [object]$SelectedIncident,

        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [hashtable]$SelectedAlertIdByIncidentId,

        [Parameter(Mandatory)]
        [ref]$SelectedAlert,

        [Parameter(Mandatory)]
        [ref]$SelectedAlertIndex,

        [Parameter(Mandatory)]
        [ref]$VisibleAlerts,

        [Parameter(Mandatory)]
        [ref]$VisibleAlertIncidentId
    )

    foreach ($jobEntry in @($AlertLoadJobsByIncidentId.GetEnumerator())) {
        $incidentId = [string]$jobEntry.Key
        $job = $jobEntry.Value
        if ($job.State -notin @('Completed', 'Failed', 'Stopped')) {
            continue
        }

        $jobOutput = @()
        try {
            $jobOutput = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
        }
        catch {
            $jobOutput = @()
        }

        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        [void]$AlertLoadJobsByIncidentId.Remove($incidentId)

        if ($job.State -ne 'Completed' -or $jobOutput.Count -eq 0) {
            continue
        }

        $payload = $jobOutput[0]
        if (-not $payload.Result -or -not $payload.Result.Success) {
            continue
        }

        $loadedAlerts = @($payload.Result.Data)
        $AlertsByIncidentId[$incidentId] = $loadedAlerts

        if ($SelectedIncident -and [string]$SelectedIncident.IncidentId -eq $incidentId) {
            Restore-XdrLiveCachedAlertsForIncident -IncidentId $incidentId -AlertsByIncidentId $AlertsByIncidentId -Context $Context -SelectedAlertIdByIncidentId $SelectedAlertIdByIncidentId -SelectedAlert $SelectedAlert -SelectedAlertIndex $SelectedAlertIndex | Out-Null
            $VisibleAlerts.Value = @($Context.Data.Alerts)
            $VisibleAlertIncidentId.Value = $incidentId
        }
    }
}
