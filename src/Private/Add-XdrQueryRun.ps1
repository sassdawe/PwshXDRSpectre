function Add-XdrQueryRun {
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