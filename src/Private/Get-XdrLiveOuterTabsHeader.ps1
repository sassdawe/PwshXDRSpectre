function Get-XdrLiveOuterTabsHeader {
    <#
    .SYNOPSIS
    Builds the outer tab header markup.

    .DESCRIPTION
    Renders the full top-level tab strip markup, highlighting the active tab
    with the dashboard accent color.

    .PARAMETER TabOrder
    Ordered list of top-level tabs.

    .PARAMETER ActiveTabIndex
    Active top-level tab index.

    .OUTPUTS
    System.String

    .EXAMPLE
    Get-XdrLiveOuterTabsHeader -TabOrder $tabOrder -ActiveTabIndex $activeTabIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$TabOrder,

        [Parameter(Mandatory)]
        [int]$ActiveTabIndex
    )

    $parts = @()
    for ($i = 0; $i -lt $TabOrder.Count; $i++) {
        $tab = $TabOrder[$i]
        $label = switch ($tab) {
            'welcome' { 'Welcome' }
            'incidents' { 'Incidents' }
            'hunting' { 'Hunting' }
            'query_library' { 'Query library' }
            'quarantine' { 'Quarantine' }
            'action_center' { 'Action Center' }
            'settings' { 'Settings' }
            'help' { 'Help' }
            default { $tab }
        }

        if ($i -eq $ActiveTabIndex) {
            $parts += "[bold black on orange1]| $label |[/]"
        }
        else {
            $parts += "[deepskyblue1 on #1C1C1C]| $label |[/]"
        }
    }

    return ($parts -join ' ')
}
