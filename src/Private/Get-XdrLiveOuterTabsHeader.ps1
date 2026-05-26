function Get-XdrLiveOuterTabsHeader {
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
            $parts += "[bold black on #C0C0C0]| $label |[/]"
        }
        else {
            $parts += "[grey70 on #1C1C1C]| $label |[/]"
        }
    }

    return ($parts -join ' ')
}
