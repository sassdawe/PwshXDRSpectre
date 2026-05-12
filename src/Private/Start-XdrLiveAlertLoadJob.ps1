function Start-XdrLiveAlertLoadJob {
    <#
    .SYNOPSIS
    Starts a background alert load job for an incident.

    .DESCRIPTION
    Queues one thread job per incident to load alerts and tracks the job in a
    dictionary keyed by incident id.

    .PARAMETER Incident
    Incident object to load alerts for.

    .PARAMETER ForceReload
    Forces load even when cache exists.

    .PARAMETER ModulePath
    Module path loaded inside thread job.

    .PARAMETER Context
    Runtime context object.

    .PARAMETER AlertsByIncidentId
    Alert cache map keyed by incident id.

    .PARAMETER AlertLoadJobsByIncidentId
    Running jobs map keyed by incident id.

    .PARAMETER LogPath
    Optional dashboard log path used by thread jobs.

    .OUTPUTS
    System.Boolean

    .EXAMPLE
    Start-XdrLiveAlertLoadJob -Incident $incident -ModulePath $modulePath -Context $context -AlertsByIncidentId $cache -AlertLoadJobsByIncidentId $jobs
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Incident,

        [Parameter()]
        [switch]$ForceReload,

        [Parameter(Mandatory)]
        [string]$ModulePath,

        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [hashtable]$AlertsByIncidentId,

        [Parameter(Mandatory)]
        [hashtable]$AlertLoadJobsByIncidentId,

        [Parameter()]
        [string]$LogPath
    )

    if (-not $Incident) {
        return $false
    }

    $incidentId = [string]$Incident.IncidentId
    if ([string]::IsNullOrWhiteSpace($incidentId)) {
        return $false
    }

    if (-not $ForceReload -and $AlertsByIncidentId.ContainsKey($incidentId)) {
        return $false
    }

    if ($AlertLoadJobsByIncidentId.ContainsKey($incidentId)) {
        return $false
    }

    $job = Start-ThreadJob -ArgumentList $ModulePath, $Context, $Incident, $incidentId, $LogPath -ScriptBlock {
        param($jobModulePath, $jobContext, $jobIncident, $jobIncidentId, $jobLogPath)

        Import-Module $jobModulePath -Force | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($jobLogPath)) {
            Write-XdrLiveDashboardLog -LogPath $jobLogPath -Message "Alert preload job started. IncidentId=$jobIncidentId"
        }

        $result = Get-XdrAlerts -Context $jobContext -Incident $jobIncident

        if (-not [string]::IsNullOrWhiteSpace($jobLogPath)) {
            $resultStatus = if ($result -and $result.Success) { 'success' } else { 'failure' }
            Write-XdrLiveDashboardLog -LogPath $jobLogPath -Message "Alert preload job completed. IncidentId=$jobIncidentId Result=$resultStatus"
        }

        [pscustomobject]@{
            IncidentId = $jobIncidentId
            Result     = $result
        }
    }

    $AlertLoadJobsByIncidentId[$incidentId] = $job
    return $true
}
