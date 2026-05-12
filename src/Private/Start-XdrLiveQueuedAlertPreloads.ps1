function Start-XdrLiveQueuedAlertPreloads {
    <#
    .SYNOPSIS
    Starts queued alert preload jobs up to concurrency limit.

    .DESCRIPTION
    Dequeues incidents and starts alert load jobs while capacity is available.

    .PARAMETER AlertLoadJobsByIncidentId
    Running jobs map keyed by incident id.

    .PARAMETER MaxAlertLoadJobs
    Maximum concurrent jobs.

    .PARAMETER AlertPreloadQueue
    Incident preload queue.

    .PARAMETER ModulePath
    Module path for thread jobs.

    .PARAMETER Context
    Runtime context object.

    .PARAMETER AlertsByIncidentId
    Alert cache map keyed by incident id.

    .PARAMETER LogPath
    Optional dashboard log path passed to alert thread jobs.

    .OUTPUTS
    None

    .EXAMPLE
    Start-XdrLiveQueuedAlertPreloads -AlertLoadJobsByIncidentId $jobs -MaxAlertLoadJobs 2 -AlertPreloadQueue $queue -ModulePath $modulePath -Context $context -AlertsByIncidentId $cache
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AlertLoadJobsByIncidentId,

        [Parameter(Mandatory)]
        [int]$MaxAlertLoadJobs,

        [Parameter(Mandatory)]
        [System.Collections.Queue]$AlertPreloadQueue,

        [Parameter(Mandatory)]
        [string]$ModulePath,

        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [hashtable]$AlertsByIncidentId,

        [Parameter()]
        [string]$LogPath
    )

    while ($AlertLoadJobsByIncidentId.Count -lt $MaxAlertLoadJobs -and $AlertPreloadQueue.Count -gt 0) {
        $nextIncident = $AlertPreloadQueue.Dequeue()
        Start-XdrLiveAlertLoadJob -Incident $nextIncident -ModulePath $ModulePath -Context $Context -AlertsByIncidentId $AlertsByIncidentId -AlertLoadJobsByIncidentId $AlertLoadJobsByIncidentId -LogPath $LogPath | Out-Null
    }
}
