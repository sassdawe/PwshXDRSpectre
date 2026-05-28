function Set-XdrLiveActionPanelVisibility {
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
