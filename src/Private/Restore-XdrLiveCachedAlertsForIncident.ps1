function Restore-XdrLiveCachedAlertsForIncident {
    <#
    .SYNOPSIS
    Restores alert list and selection from incident cache.

    .DESCRIPTION
    Loads cached alerts for a selected incident, restores prior selected alert
    when possible, and updates context selection state.

    .PARAMETER IncidentId
    Incident identifier.

    .PARAMETER AlertsByIncidentId
    Cache map keyed by incident id.

    .PARAMETER Context
    Runtime context object.

    .PARAMETER SelectedAlertIdByIncidentId
    Last selected alert id map keyed by incident id.

    .PARAMETER SelectedAlert
    Selected alert reference.

    .PARAMETER SelectedAlertIndex
    Selected alert index reference.

    .OUTPUTS
    System.Boolean

    .EXAMPLE
    Restore-XdrLiveCachedAlertsForIncident -IncidentId 'inc-1' -AlertsByIncidentId $cache -Context $context -SelectedAlertIdByIncidentId $selectedMap -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IncidentId,

        [Parameter(Mandatory)]
        [hashtable]$AlertsByIncidentId,

        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [hashtable]$SelectedAlertIdByIncidentId,

        [Parameter(Mandatory)]
        [ref]$SelectedAlert,

        [Parameter(Mandatory)]
        [ref]$SelectedAlertIndex
    )

    if (-not $AlertsByIncidentId.ContainsKey($IncidentId)) {
        return $false
    }

    $Context.Data.Alerts = @($AlertsByIncidentId[$IncidentId])
    if ($Context.Data.Alerts.Count -eq 0) {
        $SelectedAlert.Value = $null
        $SelectedAlertIndex.Value = 0
        $Context.Selection.Alert = $null
        return $true
    }

    $SelectedAlertIndex.Value = 0
    if ($SelectedAlertIdByIncidentId.ContainsKey($IncidentId)) {
        $cachedSelectedAlertId = [string]$SelectedAlertIdByIncidentId[$IncidentId]
        for ($i = 0; $i -lt $Context.Data.Alerts.Count; $i++) {
            if ([string]$Context.Data.Alerts[$i].AlertId -eq $cachedSelectedAlertId) {
                $SelectedAlertIndex.Value = $i
                break
            }
        }
    }

    $SelectedAlert.Value = $Context.Data.Alerts[$SelectedAlertIndex.Value]
    $Context.Selection.Alert = $SelectedAlert.Value
    $SelectedAlertIdByIncidentId[$IncidentId] = [string]$SelectedAlert.Value.AlertId
    return $true
}
