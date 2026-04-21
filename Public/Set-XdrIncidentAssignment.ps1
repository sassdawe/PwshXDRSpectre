function Set-XdrIncidentAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [string]$IncidentId,

        [Parameter()]
        [string]$AssignedTo
    )

    if ([string]::IsNullOrWhiteSpace($AssignedTo)) {
        return Set-XdrIncidentTriage -Context $Context -IncidentId $IncidentId -ClearAssignment -SkipConfirmation
    }

    return Set-XdrIncidentTriage -Context $Context -IncidentId $IncidentId -AssignedTo $AssignedTo -SkipConfirmation
}