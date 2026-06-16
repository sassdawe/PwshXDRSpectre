function Start-XdrLiveIncidentLoadJob {
    <#
    .SYNOPSIS
    Starts a background incident load job.

    .DESCRIPTION
    Reuses an active incident load job when one is still running; otherwise,
    clones runtime context and starts a thread job to fetch incidents.

    .PARAMETER ModulePath
    Module path imported inside the thread job.

    .PARAMETER Context
    Runtime context used to seed the job payload.

    .PARAMETER Limit
    Optional maximum number of incidents to request.

    .PARAMETER ExistingJob
    Existing incident load job to reuse when still active.

    .PARAMETER LogPath
    Optional dashboard log path passed to the thread job.

    .OUTPUTS
    System.Object

    .EXAMPLE
    Start-XdrLiveIncidentLoadJob -ModulePath $modulePath -Context $context -Limit 50 -ExistingJob $incidentLoadJob
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModulePath,

        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [object]$ExistingJob,

        [Parameter()]
        [string]$LogPath
    )

    if ($ExistingJob -and $ExistingJob.State -notin @('Completed', 'Failed', 'Stopped')) {
        return $ExistingJob
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
    $jobContext.Capabilities.IncidentActions = @($Context.Capabilities.IncidentActions)

    Start-ThreadJob -ArgumentList $ModulePath, $jobContext, $Limit, $LogPath -ScriptBlock {
        param($jobModulePath, $jobContext, $jobLimit, $jobLogPath)

        Import-Module $jobModulePath -Force | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($jobLogPath)) {
            & (Get-Module PwshXDRSpectre) {
                param([string]$InnerJobLogPath)

                Write-XdrLiveDashboardLog -LogPath $InnerJobLogPath -Message 'Incident load job started.'
            } $jobLogPath
        }

        $result = Get-XdrIncidents -Context $jobContext -Limit $jobLimit

        if (-not [string]::IsNullOrWhiteSpace($jobLogPath)) {
            $resultStatus = if ($result -and $result.Success) { 'success' } else { 'failure' }
            $incidentCount = if ($result -and $result.Data) { @($result.Data).Count } else { 0 }
            & (Get-Module PwshXDRSpectre) {
                param(
                    [string]$InnerJobLogPath,
                    [string]$InnerResultStatus,
                    [int]$InnerIncidentCount
                )

                Write-XdrLiveDashboardLog -LogPath $InnerJobLogPath -Message "Incident load job completed. Result=$InnerResultStatus IncidentCount=$InnerIncidentCount"
            } $jobLogPath $resultStatus $incidentCount
        }

        [pscustomobject]@{
            Result = $result
        }
    }
}
