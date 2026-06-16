function Start-XdrLiveQueryJob {
    <#
    .SYNOPSIS
    Starts a background hunting query job.

    .DESCRIPTION
    Clones the relevant runtime context, validates the selected query and any
    existing job state, and launches a thread job to execute the query.

    .PARAMETER Query
    Query definition to execute.

    .PARAMETER ModulePath
    Module path imported inside the thread job.

    .PARAMETER Context
    Runtime context used to seed the job payload.

    .PARAMETER ExistingJob
    Existing query job to reuse or reject when still running.

    .PARAMETER LogPath
    Optional dashboard log path passed to the thread job.

    .OUTPUTS
    System.Object

    .EXAMPLE
    Start-XdrLiveQueryJob -Query $selectedQuery -ModulePath $modulePath -Context $context -ExistingJob $queryExecutionJob
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Query,

        [Parameter(Mandatory)]
        [string]$ModulePath,

        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter()]
        [object]$ExistingJob,

        [Parameter()]
        [string]$LogPath
    )

    if (-not $Query) {
        return $null
    }

    if ($ExistingJob -and $ExistingJob.State -notin @('Completed', 'Failed', 'Stopped')) {
        return $null
    }

    $queryId = [string]$Query.id
    if ([string]::IsNullOrWhiteSpace($queryId)) {
        return $null
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
    $jobContext.Selection.Incident = if ($null -ne $Context.Selection.Incident) {
        [System.Management.Automation.PSSerializer]::Deserialize([System.Management.Automation.PSSerializer]::Serialize($Context.Selection.Incident))
    }
    else {
        $null
    }
    $jobContext.Selection.Entity = if ($null -ne $Context.Selection.Entity) {
        [System.Management.Automation.PSSerializer]::Deserialize([System.Management.Automation.PSSerializer]::Serialize($Context.Selection.Entity))
    }
    else {
        $null
    }

    $job = Start-ThreadJob -ArgumentList $ModulePath, $jobContext, $Query, $queryId, $LogPath -ScriptBlock {
        param($jobModulePath, $jobContext, $jobQuery, $jobQueryId, $jobLogPath)

        Import-Module $jobModulePath -Force | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($jobLogPath)) {
            & (Get-Module PwshXDRSpectre) {
                param([string]$InnerJobLogPath, [string]$InnerJobQueryId)

                Write-XdrLiveDashboardLog -LogPath $InnerJobLogPath -Message "Hunting query job started. QueryId=$InnerJobQueryId"
            } $jobLogPath $jobQueryId
        }

        $result = Invoke-XdrHuntingQuery -Context $jobContext -Query $jobQuery

        if (-not [string]::IsNullOrWhiteSpace($jobLogPath)) {
            $resultStatus = if ($result -and $result.Success) { 'success' } else { 'failure' }
            & (Get-Module PwshXDRSpectre) {
                param(
                    [string]$InnerJobLogPath,
                    [string]$InnerJobQueryId,
                    [string]$InnerResultStatus
                )

                Write-XdrLiveDashboardLog -LogPath $InnerJobLogPath -Message "Hunting query job completed. QueryId=$InnerJobQueryId Result=$InnerResultStatus"
            } $jobLogPath $jobQueryId $resultStatus
        }

        [pscustomobject]@{
            QueryId = $jobQueryId
            Result  = $result
        }
    }

    return $job
}