function Get-PanelBorderColor {
    <#
    .SYNOPSIS
    Returns the border color for a panel.

    .DESCRIPTION
    Uses the accent color for the active panel and the base color for all other
    panels.

    .PARAMETER PanelName
    The panel being rendered.

    .PARAMETER ActivePanel
    The current active panel.

    .PARAMETER AccentColor
    Accent color for active panel.

    .PARAMETER BaseColor
    Default color for inactive panels.

    .OUTPUTS
    System.String

    .EXAMPLE
    Get-PanelBorderColor -PanelName 'alert_list' -ActivePanel 'incident_list' -AccentColor 'Orange1'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PanelName,

        [Parameter(Mandatory)]
        [string]$ActivePanel,

        [Parameter(Mandatory)]
        [string]$AccentColor,

        [Parameter()]
        [string]$BaseColor = 'deepskyblue1'
    )

    if ($PanelName -eq $ActivePanel) {
        return $AccentColor
    }

    return $BaseColor
}
