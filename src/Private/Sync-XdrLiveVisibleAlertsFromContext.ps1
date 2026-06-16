function Sync-XdrLiveVisibleAlertsFromContext {
    <#
    .SYNOPSIS
    Rebinds visible alerts from runtime context.

    .DESCRIPTION
    Copies the current alert collection from runtime context into the visible
    alert state and records the associated incident id.

    .PARAMETER Context
    Runtime context containing the current alert collection.

    .PARAMETER VisibleAlerts
    Reference to the visible alert collection.

    .PARAMETER VisibleAlertIncidentId
    Reference to the incident id backing the visible alert collection.

    .PARAMETER Incident
    Incident that owns the visible alert collection.

    .OUTPUTS
    None

    .EXAMPLE
    Sync-XdrLiveVisibleAlertsFromContext -Context $context -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -Incident $selectedIncident
    #>
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
