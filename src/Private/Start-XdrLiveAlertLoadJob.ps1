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

    .PARAMETER RestoreSelectionOnCompletion
    When set, completed job processing may update the visible alert selection for
    the currently selected incident. Leave unset for background prefetch jobs that
    should only warm cache.

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

        [Parameter()]
        [switch]$RestoreSelectionOnCompletion,

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

    $jobContext = New-XdrRuntimeContext -TenantId ([string]$Context.Session.TenantId) -ClientId ([string]$Context.Session.ClientId) -Mode 'live' -ThemeColor ([string]$Context.Ui.ThemeColor)
    $jobContext.Session.Analyst = $Context.Session.Analyst
    $jobContext.Session.IsConnected = $Context.Session.IsConnected
    $jobContext.Session.PermissionHealth = [pscustomobject][ordered]@{
        HasSufficientWritePermissions = $Context.Session.PermissionHealth.HasSufficientWritePermissions
        DetectionSource               = $Context.Session.PermissionHealth.DetectionSource
        RequiredPermissions           = @($Context.Session.PermissionHealth.RequiredPermissions)
        AvailablePermissions          = @($Context.Session.PermissionHealth.AvailablePermissions)
        LastUpdatedAt                 = $Context.Session.PermissionHealth.LastUpdatedAt
    }
    $jobContext.Capabilities.AlertActions = @($Context.Capabilities.AlertActions)

    $job = Start-ThreadJob -ArgumentList $ModulePath, $jobContext, $Incident, $incidentId, $LogPath, $RestoreSelectionOnCompletion.IsPresent -ScriptBlock {
        param($jobModulePath, $jobContext, $jobIncident, $jobIncidentId, $jobLogPath, $jobRestoreSelectionOnCompletion)

        Import-Module $jobModulePath -Force | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($jobLogPath)) {
            & (Get-Module PwshXDRSpectre) {
                param([string]$InnerJobLogPath, [string]$InnerJobIncidentId)

                Write-XdrLiveDashboardLog -LogPath $InnerJobLogPath -Message "Alert preload job started. IncidentId=$InnerJobIncidentId"
            } $jobLogPath $jobIncidentId
        }

        $result = Get-XdrAlerts -Context $jobContext -Incident $jobIncident -SkipContextUpdate

        if (-not [string]::IsNullOrWhiteSpace($jobLogPath)) {
            $resultStatus = if ($result -and $result.Success) { 'success' } else { 'failure' }
            $resultAlertCount = if ($result -and $result.Data) { @($result.Data).Count } else { 0 }
            $resultMessage = if ($result -and $result.Message) { [regex]::Replace([string]$result.Message, '\s+', ' ').Trim() } else { '' }
            & (Get-Module PwshXDRSpectre) {
                param(
                    [string]$InnerJobLogPath,
                    [string]$InnerJobIncidentId,
                    [string]$InnerResultStatus,
                    [int]$InnerResultAlertCount,
                    [string]$InnerResultMessage
                )

                Write-XdrLiveDashboardLog -LogPath $InnerJobLogPath -Message "Alert preload job completed. IncidentId=$InnerJobIncidentId Result=$InnerResultStatus AlertCount=$InnerResultAlertCount Message=$InnerResultMessage"
            } $jobLogPath $jobIncidentId $resultStatus $resultAlertCount $resultMessage
        }

        [pscustomobject]@{
            IncidentId                  = $jobIncidentId
            RestoreSelectionOnCompletion = [bool]$jobRestoreSelectionOnCompletion
            Result                      = $result
        }
    }

    $AlertLoadJobsByIncidentId[$incidentId] = $job
    return $true
}
