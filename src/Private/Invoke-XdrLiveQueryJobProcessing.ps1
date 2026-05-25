function Invoke-XdrLiveQueryJobProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ref]$QueryJob,

        [Parameter(Mandatory)]
        [hashtable]$QueryResultsByQueryId,

        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter()]
        [object]$SelectedQuery,

        [Parameter(Mandatory)]
        [ref]$SelectedQueryResult
    )

    $job = $QueryJob.Value
    if (-not $job) {
        return
    }

    if ($job.State -notin @('Completed', 'Failed', 'Stopped')) {
        return
    }

    $jobOutput = @()
    try {
        $jobOutput = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
    }
    catch {
        $jobOutput = @()
    }

    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    $QueryJob.Value = $null

    if ($job.State -ne 'Completed' -or $jobOutput.Count -eq 0) {
        $SelectedQueryResult.Value = $null
        Set-LiveStatusMessage -Context $Context -Message 'Hunting query job did not complete successfully.' -Level 'warning'
        return
    }

    $payload = $jobOutput[0]
    if (-not $payload.Result) {
        $SelectedQueryResult.Value = $null
        Set-LiveStatusMessage -Context $Context -Message 'Hunting query job returned no result payload.' -Level 'warning'
        return
    }

    if ($payload.Result.Data -and $payload.Result.Data.PSObject.Properties.Name -contains 'QueryRun' -and $payload.Result.Data.QueryRun) {
        $Context.Data.QueryRuns = @($Context.Data.QueryRuns + $payload.Result.Data.QueryRun)
    }

    if ($payload.Result.Success -and -not [string]::IsNullOrWhiteSpace([string]$payload.QueryId) -and $payload.Result.Data) {
        $QueryResultsByQueryId[[string]$payload.QueryId] = $payload.Result.Data
    }

    $selectedQueryId = if ($SelectedQuery) { [string]$SelectedQuery.id } else { '' }
    if (-not [string]::IsNullOrWhiteSpace([string]$payload.QueryId) -and [string]$payload.QueryId -eq $selectedQueryId -and $payload.Result.Success) {
        $SelectedQueryResult.Value = $QueryResultsByQueryId[[string]$payload.QueryId]
    }

    Set-StatusFromResult -Context $Context -Result $payload.Result
}