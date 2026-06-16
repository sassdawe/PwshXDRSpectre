function Clear-XdrLiveVisibleAlerts {
    <#
    .SYNOPSIS
    Clears the alert list currently shown in the dashboard.

    .DESCRIPTION
    Resets the visible alert collection and clears the incident id associated
    with the current alert panel binding.

    .PARAMETER VisibleAlerts
    Reference to the currently visible alert collection.

    .PARAMETER VisibleAlertIncidentId
    Reference to the incident id bound to the visible alert collection.

    .OUTPUTS
    None

    .EXAMPLE
    Clear-XdrLiveVisibleAlerts -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ref]$VisibleAlerts,

        [Parameter(Mandatory)]
        [ref]$VisibleAlertIncidentId
    )

    $VisibleAlerts.Value = @()
    $VisibleAlertIncidentId.Value = $null
}
