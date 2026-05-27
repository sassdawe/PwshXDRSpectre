function Set-XdrLiveActiveTab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TabName,

        [Parameter(Mandatory)]
        [string[]]$TabOrder,

        [Parameter(Mandatory)]
        [ref]$PanelOrder,

        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [ref]$ActiveTabIndex,

        [Parameter(Mandatory)]
        [ref]$ActiveTab,

        [Parameter(Mandatory)]
        [ref]$IsQueryMode,

        [Parameter(Mandatory)]
        [ref]$ActivePanel,

        [Parameter(Mandatory)]
        [ref]$ActivePanelIndex,

        [Parameter(Mandatory)]
        [ref]$SelectedActionIndex,

        [Parameter(Mandatory)]
        [ref]$SelectedQueryIndex,

        [Parameter(Mandatory)]
        [ref]$SelectedQuery,

        [Parameter(Mandatory)]
        [ref]$SelectedQueryResult,

        [Parameter(Mandatory)]
        [hashtable]$QueryResultsByCacheKey
    )

    $targetTabIndex = [array]::IndexOf($TabOrder, $TabName)
    if ($targetTabIndex -lt 0) {
        return
    }

    $ActiveTabIndex.Value = $targetTabIndex
    $ActiveTab.Value = $TabOrder[$ActiveTabIndex.Value]
    $Context.Selection.Tab = $ActiveTab.Value
    $IsQueryMode.Value = ($ActiveTab.Value -eq 'hunting')
    $PanelOrder.Value = @(Get-XdrLivePanelOrder -TabName $ActiveTab.Value)

    if ($PanelOrder.Value.Count -gt 0) {
        $ActivePanelIndex.Value = 0
        $ActivePanel.Value = $PanelOrder.Value[$ActivePanelIndex.Value]
        $Context.Selection.Panel = $ActivePanel.Value
    }

    $SelectedActionIndex.Value = 0

    if ($IsQueryMode.Value) {
        Sync-XdrSelectedQuery -Context $Context -SelectedQueryIndex $SelectedQueryIndex -SelectedQuery $SelectedQuery -SelectedQueryResult $SelectedQueryResult -QueryResultsByCacheKey $QueryResultsByCacheKey
    }
}
