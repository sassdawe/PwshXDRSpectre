function Get-XdrIncidentDetailsTabHeader {
    <#
    .SYNOPSIS
    Returns the tab header markup for incident details view.

    .DESCRIPTION
    Produces the two-state header markup used to show whether the incident
    details or entities tab is currently active.

    .PARAMETER CurrentTab
    The currently active incident-details tab.

    .OUTPUTS
    System.String

    .EXAMPLE
    Get-XdrIncidentDetailsTabHeader -CurrentTab 'entities'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrentTab
    )

    if ([string]$CurrentTab -eq 'entities') {
        return '[deepskyblue1 on #1C1C1C]| Incident details |[/] [bold black on orange1]| Entities |[/] [grey](ALT+D to switch)[/]'
    }

    return '[bold black on orange1]| Incident details |[/] [deepskyblue1 on #1C1C1C]| Entities |[/] [grey](ALT+E to switch)[/]'
}
