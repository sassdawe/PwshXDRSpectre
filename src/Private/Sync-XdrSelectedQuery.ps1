function Sync-XdrSelectedQuery {
    <#
    .SYNOPSIS
    Synchronizes selected query state with the query catalog.

    .DESCRIPTION
    Clamps the selected query index, updates the selected query reference, and
    rebinds the visible query result from the cache for the resolved context.

    .PARAMETER Context
    Runtime context containing the query catalog and selection state.

    .PARAMETER SelectedQueryIndex
    Reference to the selected query index.

    .PARAMETER SelectedQuery
    Reference to the selected query object.

    .PARAMETER SelectedQueryResult
    Reference to the selected query result.

    .PARAMETER QueryResultsByCacheKey
    Query result cache keyed by query and context snapshot.

    .OUTPUTS
    None

    .EXAMPLE
    Sync-XdrSelectedQuery -Context $context -SelectedQueryIndex ([ref]$selectedQueryIndex) -SelectedQuery ([ref]$selectedQuery) -SelectedQueryResult ([ref]$selectedQueryResult) -QueryResultsByCacheKey $queryResultsByCacheKey
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [ref]$SelectedQueryIndex,

        [Parameter(Mandatory)]
        [ref]$SelectedQuery,

        [Parameter(Mandatory)]
        [ref]$SelectedQueryResult,

        [Parameter(Mandatory)]
        [hashtable]$QueryResultsByCacheKey
    )

    $queryCatalog = @($Context.Data.QueryCatalog)
    if ($queryCatalog.Count -eq 0) {
        $SelectedQueryIndex.Value = 0
        $SelectedQuery.Value = $null
        $SelectedQueryResult.Value = $null
        return
    }

    $SelectedQueryIndex.Value = [Math]::Min([Math]::Max($SelectedQueryIndex.Value, 0), $queryCatalog.Count - 1)
    $SelectedQuery.Value = $queryCatalog[$SelectedQueryIndex.Value]

    $selectedQueryCacheKey = $null
    $parameterResolution = Resolve-XdrQueryParameters -Query $SelectedQuery.Value -Context $Context
    if (-not $parameterResolution.IsBlocked) {
        $selectedQueryCacheKey = Get-XdrQueryResultCacheKey -QueryId ([string]$SelectedQuery.Value.id) -ContextSnapshot ([pscustomobject]$parameterResolution.Parameters)
    }

    $SelectedQueryResult.Value = if (-not [string]::IsNullOrWhiteSpace([string]$selectedQueryCacheKey) -and $QueryResultsByCacheKey.ContainsKey([string]$selectedQueryCacheKey)) { $QueryResultsByCacheKey[[string]$selectedQueryCacheKey] } else { $null }
}
