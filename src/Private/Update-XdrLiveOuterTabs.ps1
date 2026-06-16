function Update-XdrLiveOuterTabs {
    <#
    .SYNOPSIS
    Refreshes the outer tab header on the dashboard frame.

    .DESCRIPTION
    Rebuilds the tab header markup for the current active tab and updates the
    screen layout frame that hosts the dashboard.

    .PARAMETER DashboardFrame
    Dashboard frame panel to update.

    .PARAMETER ScreenLayout
    Parent screen layout containing the dashboard frame slot.

    .PARAMETER TabOrder
    Ordered list of top-level tabs.

    .PARAMETER ActiveTabIndex
    Active top-level tab index.

    .OUTPUTS
    None

    .EXAMPLE
    Update-XdrLiveOuterTabs -DashboardFrame $dashboardFrame -ScreenLayout $screenLayout -TabOrder $tabOrder -ActiveTabIndex $activeTabIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$DashboardFrame,

        [Parameter(Mandatory)]
        [object]$ScreenLayout,

        [Parameter(Mandatory)]
        [string[]]$TabOrder,

        [Parameter(Mandatory)]
        [int]$ActiveTabIndex
    )

    $outerTabsHeader = Get-XdrLiveOuterTabsHeader -TabOrder $TabOrder -ActiveTabIndex $ActiveTabIndex
    $DashboardFrame.Header = [Spectre.Console.PanelHeader]::new($outerTabsHeader, [Spectre.Console.Justify]::Left)
    $ScreenLayout['dashboard_frame'].Update($DashboardFrame) | Out-Null
}
