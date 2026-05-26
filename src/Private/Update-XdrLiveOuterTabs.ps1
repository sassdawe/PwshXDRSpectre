function Update-XdrLiveOuterTabs {
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
