function Get-XdrQueryResultCacheKey {
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