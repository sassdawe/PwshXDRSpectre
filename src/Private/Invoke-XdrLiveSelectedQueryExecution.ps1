function Invoke-XdrLiveSelectedQueryExecution {
    <#
    .SYNOPSIS
    Starts execution of the currently selected hunting query.

    .DESCRIPTION
    Validates the current selection and running-job state, then starts the
    background query job and emits a dashboard status message.

    .PARAMETER SelectedQuery
    Currently selected query definition.

    .PARAMETER QueryExecutionJob
    Reference to the active query execution job.

    .PARAMETER ModulePath
    Module path imported inside the background job.

    .PARAMETER Context
    Runtime context used for execution and status updates.

    .PARAMETER LogPath
    Optional log path passed to the query job.

    .OUTPUTS
    None

    .EXAMPLE
    Invoke-XdrLiveSelectedQueryExecution -SelectedQuery $selectedQuery -QueryExecutionJob ([ref]$queryExecutionJob) -ModulePath $modulePath -Context $context
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$SelectedQuery,

        [Parameter(Mandatory)]
        [ref]$QueryExecutionJob,

        [Parameter(Mandatory)]
        [string]$ModulePath,

        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter()]
        [string]$LogPath
    )

    if (-not $SelectedQuery) {
        Set-LiveStatusMessage -Context $Context -Message 'No hunting query is selected.' -Level 'warning'
        return
    }

    if ($QueryExecutionJob.Value -and $QueryExecutionJob.Value.State -notin @('Completed', 'Failed', 'Stopped')) {
        Set-LiveStatusMessage -Context $Context -Message 'A hunting query is already running.' -Level 'warning'
        return
    }

    $QueryExecutionJob.Value = Start-XdrLiveQueryJob -Query $SelectedQuery -ModulePath $ModulePath -Context $Context -ExistingJob $QueryExecutionJob.Value -LogPath $LogPath
    if ($QueryExecutionJob.Value) {
        Set-LiveStatusMessage -Context $Context -Message "Running hunting query: $([string]$SelectedQuery.name)" -Level 'info'
    }
    else {
        Set-LiveStatusMessage -Context $Context -Message 'Unable to start hunting query job.' -Level 'warning'
    }
}
