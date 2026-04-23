function Get-XdrTriageOptions {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Policy = (Get-XdrTriagePolicy)
    )

    [pscustomobject]@{
        IncidentStatuses        = @($Policy.incidentStatusMap)
        AlertStatuses           = @($Policy.alertStatusMap)
        IncidentClassifications = @($Policy.classifications)
        IncidentDeterminations  = @($Policy.determinations)
        DefaultResolvingComment = $Policy.defaultResolvingComment
    }
}