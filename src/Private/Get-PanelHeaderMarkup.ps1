function Get-PanelHeaderMarkup {
    <#
    .SYNOPSIS
    Creates panel header markup with active state highlighting.

    .DESCRIPTION
    Returns a bold, colored header when the panel is active and a neutral
    header when it is inactive.

    .PARAMETER PanelName
    The panel being rendered.

    .PARAMETER Title
    The display title.

    .PARAMETER ActivePanel
    The current active panel.

    .PARAMETER Color
    Accent color used when active.

    .OUTPUTS
    System.String

    .EXAMPLE
    Get-PanelHeaderMarkup -PanelName 'incident_list' -Title 'Incident List' -ActivePanel 'incident_list' -Color 'Orange1'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PanelName,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$ActivePanel,

        [Parameter(Mandatory)]
        [string]$Color
    )

    if ($PanelName -eq $ActivePanel) {
        return "[bold ${Color}]$Title (ACTIVE)[/]"
    }

    return "[white]$Title[/]"
}
