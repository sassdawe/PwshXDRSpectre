function Set-XdrLiveActiveTab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TabName,

        [Parameter(Mandatory)]
        [string[]]$TabOrder,

        [Parameter(Mandatory)]
        [string[]]$PanelOrder,

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

    if ($IsQueryMode.Value) {
        $ActivePanel.Value = 'incidents'
        $ActivePanelIndex.Value = [array]::IndexOf($PanelOrder, 'incidents')
        $Context.Selection.Panel = $ActivePanel.Value
        $SelectedActionIndex.Value = 0
        Sync-XdrSelectedQuery -Context $Context -SelectedQueryIndex $SelectedQueryIndex -SelectedQuery $SelectedQuery -SelectedQueryResult $SelectedQueryResult -QueryResultsByCacheKey $QueryResultsByCacheKey
    }
}
