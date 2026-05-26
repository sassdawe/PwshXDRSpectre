function Clear-XdrLiveVisibleAlerts {
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
