function Invoke-XdrLiveSelectedQueryExecution {
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
