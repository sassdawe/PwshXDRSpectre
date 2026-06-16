function Add-XdrLiveAlertPreloads {
    <#
    .SYNOPSIS
    Rebuilds the alert preload queue from incident list.

    .DESCRIPTION
    Clears the queue and enqueues incidents that are not cached and not already
    being loaded.

    .PARAMETER Incidents
    Incident collection.

    .PARAMETER AlertPreloadQueue
    Incident preload queue.

    .PARAMETER AlertsByIncidentId
    Alert cache map keyed by incident id.

    .PARAMETER AlertLoadJobsByIncidentId
    Running jobs map keyed by incident id.

    .OUTPUTS
    None

    .EXAMPLE
    Add-XdrLiveAlertPreloads -Incidents $context.Data.Incidents -AlertPreloadQueue $queue -AlertsByIncidentId $cache -AlertLoadJobsByIncidentId $jobs
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Incidents,

        [Parameter(Mandatory)]
        [System.Collections.Queue]$AlertPreloadQueue,

        [Parameter(Mandatory)]
        [hashtable]$AlertsByIncidentId,

        [Parameter(Mandatory)]
        [hashtable]$AlertLoadJobsByIncidentId
    )

    $AlertPreloadQueue.Clear()
    foreach ($incident in @($Incidents)) {
        if (-not $incident) {
            continue
        }

        $incidentId = [string]$incident.IncidentId
        if ([string]::IsNullOrWhiteSpace($incidentId)) {
            continue
        }

        if ($AlertsByIncidentId.ContainsKey($incidentId) -or $AlertLoadJobsByIncidentId.ContainsKey($incidentId)) {
            continue
        }

        $AlertPreloadQueue.Enqueue($incident)
    }
}
