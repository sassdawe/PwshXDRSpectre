function Add-XdrQueryRun {
    <#
    .SYNOPSIS
    Records a completed hunting query run in runtime state.

    .DESCRIPTION
    Builds a query-run record with execution metadata and appends it to the
    runtime context query history collection.

    .PARAMETER Context
    Runtime context object that stores query activity.

    .PARAMETER QueryId
    Unique query identifier.

    .PARAMETER QueryName
    Display name of the executed query.

    .PARAMETER ContextSnapshot
    Resolved context values used for the execution.

    .PARAMETER DurationMs
    Query duration in milliseconds.

    .PARAMETER Status
    Execution outcome.

    .PARAMETER RowCount
    Number of rows returned by the query.

    .PARAMETER ErrorMessage
    Optional failure detail for unsuccessful runs.

    .OUTPUTS
    System.Management.Automation.PSCustomObject

    .EXAMPLE
    Add-XdrQueryRun -Context $context -QueryId 'device-process-tree' -QueryName 'Device process tree' -ContextSnapshot @{ IncidentId = '1' } -DurationMs 250 -Status Success -RowCount 10
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [string]$QueryId,

        [Parameter(Mandatory)]
        [string]$QueryName,

        [Parameter(Mandatory)]
        [hashtable]$ContextSnapshot,

        [Parameter(Mandatory)]
        [int]$DurationMs,

        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Failed', 'NoResults')]
        [string]$Status,

        [Parameter()]
        [int]$RowCount = 0,

        [Parameter()]
        [string]$ErrorMessage
    )

    $queryRun = [pscustomobject][ordered]@{
        RunId           = ([guid]::NewGuid()).Guid
        QueryId         = $QueryId
        QueryName       = $QueryName
        ContextSnapshot = [pscustomobject]$ContextSnapshot
        ExecutedAt      = Get-Date
        DurationMs      = $DurationMs
        Status          = $Status
        RowCount        = $RowCount
        ErrorMessage    = $ErrorMessage
    }

    $Context.Data.QueryRuns = @($Context.Data.QueryRuns) + $queryRun
    return $queryRun
}