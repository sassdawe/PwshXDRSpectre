function Set-XdrIncidentAssignment {
    <#
        .SYNOPSIS
        Assigns or clears the analyst assignment on a Microsoft Defender XDR incident.

        .DESCRIPTION
        A focused wrapper around Set-XdrIncidentTriage that handles only the assignment
        concern. Passing an AssignedTo value assigns the incident; omitting it (or
        passing an empty string) clears the current assignment.

        .PARAMETER Context
        The runtime context object that holds session, capability, and selection state.

        .PARAMETER IncidentId
        The unique identifier of the incident to update.

        .PARAMETER AssignedTo
        The UPN or display name of the analyst to assign the incident to.
        Omit or pass an empty string to clear the existing assignment.

        .OUTPUTS
        PSCustomObject containing Success, Operation, Message, Data, Error, and Metadata
        properties.

        .EXAMPLE
        Set-XdrIncidentAssignment -Context $ctx -IncidentId 'inc-42' -AssignedTo 'analyst@contoso.com'

        .EXAMPLE
        Set-XdrIncidentAssignment -Context $ctx -IncidentId 'inc-42'

        .NOTES
        Confirmation is skipped by default; use Set-XdrIncidentTriage directly if
        confirmation prompts are required.
    #>
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