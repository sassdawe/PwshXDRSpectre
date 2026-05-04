function Get-PanelBorderStyle {
    <#
    .SYNOPSIS
    Returns the border style for a panel.

    .DESCRIPTION
    Uses a double-line border for the active panel and the default rounded
    border for all other panels.

    .PARAMETER PanelName
    The panel being rendered.

    .PARAMETER ActivePanel
    The current active panel.

    .PARAMETER ActiveBorder
    Border style used for the active panel.

    .PARAMETER InactiveBorder
    Border style used for inactive panels.

    .OUTPUTS
    System.String

    .EXAMPLE
    Get-PanelBorderStyle -PanelName 'alerts' -ActivePanel 'alerts'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PanelName,

        [Parameter(Mandatory)]
        [string]$ActivePanel,

        [Parameter()]
        [string]$ActiveBorder = 'Double',

        [Parameter()]
        [string]$InactiveBorder = 'Rounded'
    )

    if ($PanelName -eq $ActivePanel) {
        return $ActiveBorder
    }

    return $InactiveBorder
}
