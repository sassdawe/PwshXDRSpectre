function Set-XdrLiveActionPanelVisibility {
    <#
    .SYNOPSIS
    Shows or hides the live dashboard action panel.

    .DESCRIPTION
    Rebuilds the dashboard layout for the requested action-panel visibility,
    updates panel ordering, and rebinds active panel state when necessary.

    .PARAMETER Visible
    Indicates whether the action panel should be visible.

    .PARAMETER Layout
    Reference to the root dashboard layout.

    .PARAMETER DashboardFrame
    Reference to the formatted dashboard frame panel.

    .PARAMETER ScreenLayout
    Parent screen layout that hosts the dashboard frame.

    .PARAMETER TabOrder
    Ordered list of available top-level tabs.

    .PARAMETER ActiveTabIndex
    Current active tab index.

    .PARAMETER ActiveTab
    Current active tab name.

    .PARAMETER PanelOrder
    Reference to the current panel order.

    .PARAMETER ActivePanel
    Reference to the active panel name.

    .PARAMETER ActivePanelIndex
    Reference to the active panel index.

    .PARAMETER Context
    Runtime context updated with the active panel selection.

    .OUTPUTS
    None

    .EXAMPLE
    Set-XdrLiveActionPanelVisibility -Visible $true -Layout ([ref]$layout) -DashboardFrame ([ref]$dashboardFrame) -ScreenLayout $screenLayout -TabOrder $tabOrder -ActiveTabIndex $activeTabIndex -ActiveTab $activeTab -PanelOrder ([ref]$panelOrder) -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -Context $context
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$Visible,

        [Parameter(Mandatory)]
        [ref]$Layout,

        [Parameter(Mandatory)]
        [ref]$DashboardFrame,

        [Parameter(Mandatory)]
        [object]$ScreenLayout,

        [Parameter(Mandatory)]
        [string[]]$TabOrder,

        [Parameter(Mandatory)]
        [int]$ActiveTabIndex,

        [Parameter(Mandatory)]
        [string]$ActiveTab,

        [Parameter(Mandatory)]
        [ref]$PanelOrder,

        [Parameter(Mandatory)]
        [ref]$ActivePanel,

        [Parameter(Mandatory)]
        [ref]$ActivePanelIndex,

        [Parameter(Mandatory)]
        [object]$Context
    )

    $Layout.Value = New-XdrLiveDashboardLayout -ActionPanelVisible:$Visible
    $DashboardFrame.Value = Format-SpectrePanel -Data $Layout.Value -Header ' ' -Color 'deepskyblue1' -Border 'Rounded' -Expand
    $PanelOrder.Value = @(Get-XdrLivePanelOrder -TabName $ActiveTab -HideActionPanel:(-not $Visible))

    if ($PanelOrder.Value.Count -gt 0 -and $PanelOrder.Value -notcontains $ActivePanel.Value) {
        $ActivePanelIndex.Value = 0
        $ActivePanel.Value = $PanelOrder.Value[$ActivePanelIndex.Value]
        $Context.Selection.Panel = $ActivePanel.Value
    }
    elseif ($PanelOrder.Value.Count -gt 0) {
        $ActivePanelIndex.Value = [array]::IndexOf($PanelOrder.Value, $ActivePanel.Value)
        $Context.Selection.Panel = $ActivePanel.Value
    }

    Update-XdrLiveOuterTabs -DashboardFrame $DashboardFrame.Value -ScreenLayout $ScreenLayout -TabOrder $TabOrder -ActiveTabIndex $ActiveTabIndex
}
