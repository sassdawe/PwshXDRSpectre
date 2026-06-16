function Get-XdrLivePanelOrder {
    <#
    .SYNOPSIS
    Returns the panel navigation order for a top-level tab.

    .DESCRIPTION
    Maps the active outer tab to the logical panel sequence used for focus and
    navigation, optionally omitting the action panel.

    .PARAMETER TabName
    Active top-level tab name.

    .PARAMETER HideActionPanel
    Removes the action panel from the returned order when set.

    .OUTPUTS
    System.String[]

    .EXAMPLE
    Get-XdrLivePanelOrder -TabName 'hunting'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TabName,

        [Parameter()]
        [switch]$HideActionPanel
    )

    $panelOrder = switch ($TabName) {
        'hunting' { @('query_catalog', 'query_preview', 'query_activity', 'query_actions') }
        'welcome' { @('welcome_overview', 'welcome_info', 'welcome_announcements', 'welcome_actions') }
        'query_library' { @('query_library_list', 'query_library_settings', 'query_library_versions', 'query_library_actions') }
        'quarantine' { @('quarantine_items', 'quarantine_status', 'quarantine_info', 'quarantine_actions') }
        'action_center' { @('action_center_items', 'action_center_status', 'action_center_info', 'action_center_actions') }
        'settings' { @('settings_overview', 'settings_debug', 'settings_logs', 'settings_actions') }
        'help' { @('help_topics', 'help_tips', 'help_faq', 'help_actions') }
        default { @('incident_list', 'incident_details', 'alert_list', 'incident_actions') }
    }

    if ($HideActionPanel.IsPresent) {
        return @($panelOrder | Where-Object { $_ -notmatch '_actions$' })
    }

    return @($panelOrder)
}
