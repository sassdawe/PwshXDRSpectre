function Get-XdrLiveAlertPrefetchIndicator {
    <#
    .SYNOPSIS
    Computes alert prefetch progress indicator text.

    .DESCRIPTION
    Produces a compact progress line showing cached incident alerts, active job
    count, and queue depth. Hides the indicator after one minute of completed
    prefetch state.

    .PARAMETER Context
    Runtime context object.

    .PARAMETER AlertsByIncidentId
    Alert cache map keyed by incident id.

    .PARAMETER AlertLoadJobsByIncidentId
    Running jobs map keyed by incident id.

    .PARAMETER AlertPreloadQueue
    Incident preload queue.

    .PARAMETER PrefetchCompletedAt
    Timestamp reference for completed prefetch.

    .OUTPUTS
    System.String

    .EXAMPLE
    Get-XdrLiveAlertPrefetchIndicator -Context $context -AlertsByIncidentId $cache -AlertLoadJobsByIncidentId $jobs -AlertPreloadQueue $queue -PrefetchCompletedAt ([ref]$prefetchCompletedAt)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [hashtable]$AlertsByIncidentId,

        [Parameter(Mandatory)]
        [hashtable]$AlertLoadJobsByIncidentId,

        [Parameter(Mandatory)]
        [System.Collections.Queue]$AlertPreloadQueue,

        [Parameter(Mandatory)]
        [ref]$PrefetchCompletedAt
    )

    $barWidth = 12
    $active = $AlertLoadJobsByIncidentId.Count
    $queue = $AlertPreloadQueue.Count

    $incidentIds = @($Context.Data.Incidents |
        Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.IncidentId) } |
        ForEach-Object { [string]$_.IncidentId } |
        Select-Object -Unique)

    $total = $incidentIds.Count
    if ($total -eq 0) {
        $PrefetchCompletedAt.Value = $null
        return $null
    }

    $cached = 0
    foreach ($incidentId in $incidentIds) {
        if ($AlertsByIncidentId.ContainsKey($incidentId)) {
            $cached++
        }
    }

    $isPrefetchComplete = ($cached -ge $total -and $active -eq 0 -and $queue -eq 0)
    if ($isPrefetchComplete) {
        if ($null -eq $PrefetchCompletedAt.Value) {
            $PrefetchCompletedAt.Value = Get-Date
        }
    }
    else {
        $PrefetchCompletedAt.Value = $null
    }

    if ($null -ne $PrefetchCompletedAt.Value -and ((Get-Date) - $PrefetchCompletedAt.Value).TotalMinutes -ge 1) {
        return $null
    }

    $filled = [Math]::Min($barWidth, [Math]::Floor(($cached / $total) * $barWidth))
    $bar = ('=' * $filled) + ('.' * ($barWidth - $filled))
    return "prefetch $cached/$total $bar active:$active queue:$queue"
}
