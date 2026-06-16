function Set-XdrLiveActiveTab {
    <#
    .SYNOPSIS
    Switches the live dashboard to a different top-level tab.

    .DESCRIPTION
    Updates tab and panel state, recalculates panel order, resets action-panel
    selection, and synchronizes the selected hunting query when entering query
    mode.

    .PARAMETER TabName
    Target top-level tab name.

    .PARAMETER TabOrder
    Ordered list of available top-level tabs.

    .PARAMETER PanelOrder
    Reference to the current panel order.

    .PARAMETER Context
    Runtime context to update with tab and panel selection.

    .PARAMETER ActiveTabIndex
    Reference to the active tab index.

    .PARAMETER ActiveTab
    Reference to the active tab name.

    .PARAMETER IsQueryMode
    Reference tracking whether hunting mode is active.

    .PARAMETER ActivePanel
    Reference to the active panel name.

    .PARAMETER ActivePanelIndex
    Reference to the active panel index.

    .PARAMETER SelectedActionIndex
    Reference to the selected action index.

    .PARAMETER SelectedQueryIndex
    Reference to the selected query index.

    .PARAMETER SelectedQuery
    Reference to the selected query object.

    .PARAMETER SelectedQueryResult
    Reference to the selected query result.

    .PARAMETER QueryResultsByCacheKey
    Query result cache keyed by query id and context snapshot.

    .PARAMETER HideActionPanel
    Omits the action panel from panel order when set.

    .OUTPUTS
    None

    .EXAMPLE
    Set-XdrLiveActiveTab -TabName 'hunting' -TabOrder $tabOrder -PanelOrder ([ref]$panelOrder) -Context $context -ActiveTabIndex ([ref]$activeTabIndex) -ActiveTab ([ref]$activeTab) -IsQueryMode ([ref]$isQueryMode) -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -SelectedActionIndex ([ref]$selectedActionIndex) -SelectedQueryIndex ([ref]$selectedQueryIndex) -SelectedQuery ([ref]$selectedQuery) -SelectedQueryResult ([ref]$selectedQueryResult) -QueryResultsByCacheKey $queryResultsByCacheKey
    #>
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
        [hashtable]$QueryResultsByCacheKey,

        [Parameter()]
        [switch]$HideActionPanel
    )

    $targetTabIndex = [array]::IndexOf($TabOrder, $TabName)
    if ($targetTabIndex -lt 0) {
        return
    }

    $ActiveTabIndex.Value = $targetTabIndex
    $ActiveTab.Value = $TabOrder[$ActiveTabIndex.Value]
    $Context.Selection.Tab = $ActiveTab.Value
    $IsQueryMode.Value = ($ActiveTab.Value -eq 'hunting')
    $PanelOrder.Value = @(Get-XdrLivePanelOrder -TabName $ActiveTab.Value -HideActionPanel:$HideActionPanel.IsPresent)

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
