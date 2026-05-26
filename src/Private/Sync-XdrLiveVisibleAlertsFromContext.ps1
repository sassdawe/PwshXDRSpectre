function Sync-XdrLiveVisibleAlertsFromContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [ref]$VisibleAlerts,

        [Parameter(Mandatory)]
        [ref]$VisibleAlertIncidentId,

        [Parameter()]
        [object]$Incident
    )

    $VisibleAlerts.Value = @($Context.Data.Alerts)
    $VisibleAlertIncidentId.Value = if ($Incident) { [string]$Incident.IncidentId } else { $null }
}
