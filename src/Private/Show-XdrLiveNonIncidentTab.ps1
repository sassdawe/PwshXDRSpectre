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
        [bool]$ShowKeyboardHelpOverlay
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

    switch ($ActiveTab) {
        'welcome' {
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

    $Layout['incidents'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title $leftTitle -ActivePanel $ActivePanel -Color $Context.Ui.ThemeColor) -Data $leftData -Expand)) | Out-Null
    $Layout['incident_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title $centerTitle -ActivePanel $ActivePanel -Color $Context.Ui.ThemeColor) -Data $centerData -Expand)) | Out-Null
    $Layout['alerts'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alerts' -Title $lowerLeftTitle -ActivePanel $ActivePanel -Color $Context.Ui.ThemeColor) -Data $lowerLeftData -Expand)) | Out-Null
    $Layout['alert_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title $lowerCenterTitle -ActivePanel $ActivePanel -Color $Context.Ui.ThemeColor) -Data $lowerCenterData -Expand)) | Out-Null
    $Layout['action_status'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title $actionsTitle -ActivePanel $ActivePanel -Color $Context.Ui.ThemeColor) -Data $actionsData -Expand)) | Out-Null

    if ($CurrentHelpPanel) {
        $Layout['help'].Update($CurrentHelpPanel) | Out-Null
    }
}
