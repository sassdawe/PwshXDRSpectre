function Get-XdrQueryResultCacheKey {
    <#
    .SYNOPSIS
    Builds a cache key for a query result.

    .DESCRIPTION
    Combines the query id and sorted context snapshot values into a stable key
    so results are cached per query and resolved execution context.

    .PARAMETER QueryId
    Query identifier.

    .PARAMETER ContextSnapshot
    Resolved parameter snapshot for the query execution.

    .OUTPUTS
    System.String

    .EXAMPLE
    Get-XdrQueryResultCacheKey -QueryId 'device-process-tree' -ContextSnapshot @{ IncidentId = '1' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$QueryId,

        [Parameter()]
        [object]$ContextSnapshot
    )

    if ([string]::IsNullOrWhiteSpace($QueryId)) {
        return $null
    }

    $snapshotEntries = @()
    if ($ContextSnapshot) {
        $propertyNames = @($ContextSnapshot.PSObject.Properties.Name | Sort-Object)
        foreach ($propertyName in $propertyNames) {
            $snapshotEntries += ('{0}={1}' -f $propertyName, [string]$ContextSnapshot.$propertyName)
        }
    }

    return ('{0}|{1}' -f $QueryId, ($snapshotEntries -join ';'))
}