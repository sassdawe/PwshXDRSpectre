function Invoke-XdrLiveQueryJobProcessing {
    <#
    .SYNOPSIS
    Processes a completed hunting query background job.

    .DESCRIPTION
    Receives the query-job payload, updates cached query results, refreshes the
    selected query result when appropriate, and publishes the resulting status
    message.

    .PARAMETER QueryJob
    Reference to the active query job.

    .PARAMETER QueryResultsByCacheKey
    Result cache keyed by query and resolved context.

    .PARAMETER Context
    Runtime context to update with query history and status.

    .PARAMETER SelectedQuery
    Currently selected query definition.

    .PARAMETER SelectedQueryResult
    Reference to the current query result payload.

    .OUTPUTS
    None

    .EXAMPLE
    Invoke-XdrLiveQueryJobProcessing -QueryJob ([ref]$queryJob) -QueryResultsByCacheKey $queryResultsByCacheKey -Context $context -SelectedQuery $selectedQuery -SelectedQueryResult ([ref]$selectedQueryResult)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ref]$QueryJob,

        [Parameter(Mandatory)]
        [hashtable]$QueryResultsByCacheKey,

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
        Set-LiveStatusMessage -Context $Context -Message 'Hunting query job did not complete successfully.' -Level 'warning'
        return
    }

    $payload = $jobOutput[0]
    if (-not $payload.Result) {
        Set-LiveStatusMessage -Context $Context -Message 'Hunting query job returned no result payload.' -Level 'warning'
        return
    }

    if ($payload.Result.Data -and $payload.Result.Data.PSObject.Properties.Name -contains 'QueryRun' -and $payload.Result.Data.QueryRun) {
        $Context.Data.QueryRuns = @($Context.Data.QueryRuns + $payload.Result.Data.QueryRun)
    }

    $payloadCacheKey = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$payload.QueryId) -and $payload.Result.Data -and $payload.Result.Data.PSObject.Properties.Name -contains 'ContextSnapshot') {
        $payloadCacheKey = Get-XdrQueryResultCacheKey -QueryId ([string]$payload.QueryId) -ContextSnapshot $payload.Result.Data.ContextSnapshot
    }

    if ($payload.Result.Success -and -not [string]::IsNullOrWhiteSpace([string]$payloadCacheKey) -and $payload.Result.Data) {
        $QueryResultsByCacheKey[[string]$payloadCacheKey] = $payload.Result.Data
    }

    $selectedQueryId = if ($SelectedQuery) { [string]$SelectedQuery.id } else { '' }
    $selectedQueryCacheKey = $null
    if (-not [string]::IsNullOrWhiteSpace($selectedQueryId)) {
        $parameterResolution = Resolve-XdrQueryParameters -Query $SelectedQuery -Context $Context
        if (-not $parameterResolution.IsBlocked) {
            $selectedQueryCacheKey = Get-XdrQueryResultCacheKey -QueryId $selectedQueryId -ContextSnapshot ([pscustomobject]$parameterResolution.Parameters)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$payloadCacheKey) -and [string]$payloadCacheKey -eq $selectedQueryCacheKey -and $payload.Result.Success) {
        $SelectedQueryResult.Value = $QueryResultsByCacheKey[[string]$payloadCacheKey]
    }

    Set-StatusFromResult -Context $Context -Result $payload.Result
}