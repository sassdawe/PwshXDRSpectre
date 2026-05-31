function Show-XdrLiveNonIncidentTab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Layout,

        [Parameter(Mandatory)]
        [string]$ActiveTab,

        [Parameter(Mandatory)]
        [string]$ActivePanel,

        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter()]
        [object]$CurrentHelpPanel,

        [Parameter()]
        [string]$DashboardLogPath,

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$ClientId,

        [Parameter()]
        [object]$SelectedIncident,

        [Parameter()]
        [object]$PendingIncidentResolution,

        [Parameter()]
        [object]$PendingTextInput,

        [Parameter()]
        [object]$PendingConfirmation,

        [Parameter()]
        [hashtable]$AlertsByIncidentId,

        [Parameter()]
        [hashtable]$AlertLoadJobsByIncidentId,

        [Parameter()]
        [System.Collections.Queue]$AlertPreloadQueue,

        [Parameter()]
        [ref]$PrefetchCompletedAt,

        [Parameter()]
        [datetime]$LastRefreshAt,

        [Parameter()]
        [datetime]$HeartbeatAt,

        [Parameter()]
        [int]$HeartbeatCounter,

        [Parameter()]
        [bool]$IsQueryMode,

        [Parameter()]
        [bool]$ShowKeyboardHelpOverlay,

        [Parameter()]
        [bool]$ActionPanelVisible = $true
    )

    $leftTitle = 'Coming Soon'
    $leftData = 'This workspace is being prepared.'
    $centerTitle = 'Details'
    $centerData = 'Select another tab or return to Incidents.'
    $lowerLeftTitle = 'Status'
    $lowerLeftData = 'No data available.'
    $lowerCenterTitle = 'Preview'
    $lowerCenterData = 'No item selected.'
    $actionsTitle = 'Actions'
    $actionsData = 'No actions available on this tab.'
    $leftPanelName = 'placeholder_overview'
    $centerPanelName = 'placeholder_details'
    $lowerLeftPanelName = 'placeholder_activity'
    $lowerCenterPanelName = 'placeholder_preview'
    $actionsPanelName = 'placeholder_actions'

    switch ($ActiveTab) {
        'welcome' {
            $leftPanelName = 'welcome_overview'
            $centerPanelName = 'welcome_info'
            $lowerLeftPanelName = 'welcome_announcements'
            $lowerCenterPanelName = 'welcome_session'
            $actionsPanelName = 'welcome_actions'
            $leftTitle = 'Welcome'
            $leftData = @(
                '[white on #003366]  PwshXDRSpectre  [/]',
                '',
                'Use Alt+1..8 to switch tabs. Navigate with Tab, PgUp, and PgDn.'
            ) -join "`n"
            $centerTitle = 'Info'
            $centerData = 'Incident triage remains available on the Incidents tab.'
            $lowerLeftTitle = 'Announcements'
            $lowerLeftData = 'No announcements.'
            $lowerCenterTitle = 'Session'
            $lowerCenterData = "Tenant: $TenantId`nClient: $ClientId"
        }
        'hunting' {
            $leftPanelName = 'query_catalog'
            $centerPanelName = 'query_preview'
            $lowerLeftPanelName = 'query_activity'
            $lowerCenterPanelName = 'query_results'
            $actionsPanelName = 'query_actions'
            $leftTitle = 'Hunting - Query Catalog'
            $leftData = 'Use the query catalog to select hunting queries.'
            $centerTitle = 'Query Preview'
            $centerData = 'Selected query preview and parameters.'
            $lowerLeftTitle = 'Query Results'
            $lowerLeftData = 'Query results will appear here.'
            $lowerCenterTitle = 'Result Details'
            $lowerCenterData = 'Details for the selected result.'
            $actionsData = 'Alt+X executes the selected query when hunting mode is active.'
        }
        'query_library' {
            $leftPanelName = 'query_library_list'
            $centerPanelName = 'query_library_settings'
            $lowerLeftPanelName = 'query_library_versions'
            $lowerCenterPanelName = 'query_library_preview'
            $actionsPanelName = 'query_library_actions'
            $leftTitle = 'Query Library'
            $leftData = 'Manage saved queries and settings.'
            $centerTitle = 'Query Settings'
            $centerData = 'Query settings and metadata.'
            $lowerLeftTitle = 'Versions'
            $lowerLeftData = 'Version history and owners.'
            $lowerCenterTitle = 'Preview'
            $lowerCenterData = 'Preview selected query.'
        }
        'quarantine' {
            $leftPanelName = 'quarantine_items'
            $centerPanelName = 'quarantine_status'
            $lowerLeftPanelName = 'quarantine_info'
            $lowerCenterPanelName = 'quarantine_details'
            $actionsPanelName = 'quarantine_actions'
            $leftTitle = 'Quarantine'
            $leftData = 'Under construction.'
            $centerTitle = 'Status'
            $centerData = 'Work in progress.'
            $lowerLeftTitle = 'Info'
            $lowerLeftData = 'Under construction.'
            $lowerCenterTitle = 'Details'
            $lowerCenterData = 'Under construction.'
            $actionsData = 'Under construction.'
        }
        'action_center' {
            $leftPanelName = 'action_center_items'
            $centerPanelName = 'action_center_status'
            $lowerLeftPanelName = 'action_center_info'
            $lowerCenterPanelName = 'action_center_details'
            $actionsPanelName = 'action_center_actions'
            $leftTitle = 'Action Center'
            $leftData = 'Under construction.'
            $centerTitle = 'Status'
            $centerData = 'Work in progress.'
            $lowerLeftTitle = 'Info'
            $lowerLeftData = 'Under construction.'
            $lowerCenterTitle = 'Details'
            $lowerCenterData = 'Under construction.'
            $actionsData = 'Under construction.'
        }
        'settings' {
            $leftPanelName = 'settings_overview'
            $centerPanelName = 'settings_debug'
            $lowerLeftPanelName = 'settings_logs'
            $lowerCenterPanelName = 'settings_files'
            $actionsPanelName = 'settings_actions'
            $leftTitle = 'Settings'
            $leftData = @(
                "Input debug (Ctrl+Alt+K): $($Context.Diagnostics.InputDebugEnabled)",
                "LogPath: $DashboardLogPath",
                "ThemeColor: $($Context.Ui.ThemeColor)"
            ) -join "`n"
            $centerTitle = 'Debug'
            $centerData = 'Log files and debug flags.'
            $lowerLeftTitle = 'Logs'
            $lowerLeftData = 'Log browsing coming soon.'
            $lowerCenterTitle = 'Files'
            $lowerCenterData = 'List of recent log files.'
        }
        'help' {
            $leftPanelName = 'help_topics'
            $centerPanelName = 'help_tips'
            $lowerLeftPanelName = 'help_faq'
            $lowerCenterPanelName = 'help_support'
            $actionsPanelName = 'help_actions'
            $leftTitle = 'Help'
            $leftData = Get-XdrLiveHelpPanelContent -Context $Context -SelectedIncident $SelectedIncident -PendingIncidentResolution $PendingIncidentResolution -PendingTextInput $PendingTextInput -PendingConfirmation $PendingConfirmation -AlertsByIncidentId $AlertsByIncidentId -AlertLoadJobsByIncidentId $AlertLoadJobsByIncidentId -AlertPreloadQueue $AlertPreloadQueue -PrefetchCompletedAt $PrefetchCompletedAt -LastRefreshAt $LastRefreshAt -HeartbeatAt $HeartbeatAt -HeartbeatCounter $HeartbeatCounter -IsQueryMode:$IsQueryMode -ShowKeyboardHelpOverlay:$ShowKeyboardHelpOverlay
            $centerTitle = 'Tips'
            $centerData = 'Keyboard shortcuts and guidance.'
            $lowerLeftTitle = 'FAQ'
            $lowerLeftData = 'Frequently asked questions.'
            $lowerCenterTitle = 'Support'
            $lowerCenterData = 'Contact and support links.'
        }
    }

    $Layout[(Resolve-XdrLivePanelSlot -PanelName $leftPanelName)].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName $leftPanelName -Title $leftTitle -ActivePanel $ActivePanel -Color $Context.Ui.ThemeColor) -Data $leftData -Expand)) | Out-Null
    $Layout[(Resolve-XdrLivePanelSlot -PanelName $centerPanelName)].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName $centerPanelName -Title $centerTitle -ActivePanel $ActivePanel -Color $Context.Ui.ThemeColor) -Data $centerData -Expand)) | Out-Null
    $Layout[(Resolve-XdrLivePanelSlot -PanelName $lowerLeftPanelName)].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName $lowerLeftPanelName -Title $lowerLeftTitle -ActivePanel $ActivePanel -Color $Context.Ui.ThemeColor) -Data $lowerLeftData -Expand)) | Out-Null
    $Layout[(Resolve-XdrLivePanelSlot -PanelName $lowerCenterPanelName)].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName $lowerCenterPanelName -Title $lowerCenterTitle -ActivePanel $ActivePanel -Color $Context.Ui.ThemeColor) -Data $lowerCenterData -Expand)) | Out-Null
    if ($ActionPanelVisible) {
        $Layout[(Resolve-XdrLivePanelSlot -PanelName $actionsPanelName)].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName $actionsPanelName -Title $actionsTitle -ActivePanel $ActivePanel -Color $Context.Ui.ThemeColor) -Data $actionsData -Expand)) | Out-Null
    }

    if ($CurrentHelpPanel) {
        $Layout['help'].Update($CurrentHelpPanel) | Out-Null
    }
}
