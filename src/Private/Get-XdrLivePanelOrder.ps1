function Get-XdrLivePanelOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TabName
    )

    switch ($TabName) {
        'hunting' { return @('query_catalog', 'query_preview', 'query_activity', 'query_actions') }
        'welcome' { return @('welcome_overview', 'welcome_info', 'welcome_announcements', 'welcome_actions') }
        'query_library' { return @('query_library_list', 'query_library_settings', 'query_library_versions', 'query_library_actions') }
        'quarantine' { return @('quarantine_items', 'quarantine_status', 'quarantine_info', 'quarantine_actions') }
        'action_center' { return @('action_center_items', 'action_center_status', 'action_center_info', 'action_center_actions') }
        'settings' { return @('settings_overview', 'settings_debug', 'settings_logs', 'settings_actions') }
        'help' { return @('help_topics', 'help_tips', 'help_faq', 'help_actions') }
        default { return @('incident_list', 'incident_details', 'alert_list', 'incident_actions') }
    }
}
