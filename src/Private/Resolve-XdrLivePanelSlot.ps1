function Resolve-XdrLivePanelSlot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PanelName
    )

    switch ($PanelName) {
        { $_ -in @('incident_list', 'query_catalog', 'workflow_list', 'welcome_overview', 'query_library_list', 'quarantine_items', 'action_center_items', 'settings_overview', 'help_topics') } { return 'left_top' }
        { $_ -in @('incident_details', 'query_preview', 'workflow_overview', 'welcome_info', 'query_library_settings', 'quarantine_status', 'action_center_status', 'settings_debug', 'help_tips') } { return 'center_top' }
        { $_ -in @('alert_list', 'query_activity', 'workflow_steps', 'welcome_announcements', 'query_library_versions', 'quarantine_info', 'action_center_info', 'settings_logs', 'help_faq') } { return 'left_bottom' }
        { $_ -in @('alert_details', 'query_results', 'workflow_step_details', 'welcome_session', 'query_library_preview', 'quarantine_details', 'action_center_details', 'settings_files', 'help_support') } { return 'center_bottom' }
        { $_ -in @('incident_actions', 'query_actions', 'workflow_actions', 'welcome_actions', 'query_library_actions', 'quarantine_actions', 'action_center_actions', 'settings_actions', 'help_actions') } { return 'right_actions' }
        'help' { return 'help' }
        default { return $PanelName }
    }
}
