function Start-PwshXdrLiveDashboard {
    <#
        .SYNOPSIS
        Launches the interactive PowerShell XDR live dashboard TUI.

        .DESCRIPTION
        Connects to Microsoft Defender XDR via Microsoft Graph, loads incidents and
        alerts, and renders a full-screen terminal user interface built with
        PwshSpectreConsole. The dashboard supports keyboard-driven navigation,
        incident triage, alert status updates, analyst assignment, and real-time
        background alert prefetching.

        .PARAMETER TenantId
        The Azure AD tenant ID for the target organization.

        .PARAMETER ClientId
        The Azure AD application (client) ID used for Microsoft Graph authentication.

        .PARAMETER Limit
        Maximum number of incidents to load on startup. When 0 or not specified, all
        available incidents are retrieved.

        .PARAMETER UseDeviceCode
        When specified, uses device code flow for interactive authentication instead of
        the default browser-based interactive flow.

        .PARAMETER LogPath
        Optional path for the dashboard log file. When omitted, a timestamped log file
        is created under the user's local application data folder.

        .PARAMETER WithLogs
        Enables dashboard file logging. When not specified, no log file is created.

        .OUTPUTS
        None. The dashboard runs interactively until the user presses Ctrl+C to exit.

        .EXAMPLE
        Start-PwshXdrLiveDashboard -TenantId 'xxxxxxxx-...' -ClientId 'yyyyyyyy-...'

        .EXAMPLE
        Start-PwshXdrLiveDashboard -TenantId 'xxxxxxxx-...' -ClientId 'yyyyyyyy-...' `
            -Limit 50 -UseDeviceCode

        .NOTES
        Requires PwshSpectreConsole and Microsoft.PowerShell.ThreadJob modules.
        Press Ctrl+C to exit the dashboard.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [switch]$UseDeviceCode,

        [Parameter()]
        [switch]$WithLogs,

        [Parameter()]
        [string]$LogPath
    )

    $context = New-XdrRuntimeContext -TenantId $TenantId -ClientId $ClientId -Mode 'live' -ThemeColor 'Orange1'

    $dashboardLogPath = $null
    if ($WithLogs.IsPresent) {
        $dashboardLogPath = if ([string]::IsNullOrWhiteSpace($LogPath)) {
            $dashboardLogDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PwshXDRSpectre'
            $dashboardLogTimestamp = Get-Date -Format 'yyyyMMddTHHmmssfff'
            $dashboardLogFileName = "live-dashboard-$dashboardLogTimestamp.log"
            Join-Path $dashboardLogDirectory $dashboardLogFileName
        }
        else {
            $LogPath
        }

        $dashboardLogDirectory = Split-Path -Parent $dashboardLogPath
        if (-not [string]::IsNullOrWhiteSpace($dashboardLogDirectory)) {
            New-Item -ItemType Directory -Path $dashboardLogDirectory -Force | Out-Null
        }

        Write-Host "Dashboard log file: $dashboardLogPath"
        Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message 'Dashboard started.'
    }

    # Module name differs across environments: prefer explicit PSGallery package name first.
    $threadJobLoaded = $false
    foreach ($moduleName in @('Microsoft.PowerShell.ThreadJob', 'ThreadJob')) {
        try {
            Import-Module $moduleName -ErrorAction Stop | Out-Null
            $threadJobLoaded = $true
            break
        }
        catch {
            continue
        }
    }

    if (-not $threadJobLoaded) {
        throw "ThreadJob module is required. Install Microsoft.PowerShell.ThreadJob and ensure it is on PSModulePath."
    }

    $layout = New-SpectreLayout -Name 'root' -Rows @(
        (New-SpectreLayout -Name 'header' -MinimumSize 5 -Ratio 2 -Data 'empty'),
        (
            New-SpectreLayout -Name 'main_content' -Ratio 10 -Columns @(
                # Left column: incidents and alerts stacked
                (New-SpectreLayout -Name 'left_lists' -Ratio 2 -Rows @(
                    (New-SpectreLayout -Name 'incidents' -Ratio 1 -Data 'empty'),
                    (New-SpectreLayout -Name 'alerts' -Ratio 1 -Data 'empty')
                )),
                # Middle column: incident details and alert details stacked
                (New-SpectreLayout -Name 'center_details' -Ratio 3 -Rows @(
                    (New-SpectreLayout -Name 'incident_details' -Ratio 1 -Data 'empty'),
                    (New-SpectreLayout -Name 'alert_details' -Ratio 1 -Data 'empty')
                )),
                # Right column: actions (full height)
                (New-SpectreLayout -Name 'action_status' -Ratio 2 -Data 'empty')
            )
        ),
        (New-SpectreLayout -Name 'help' -MinimumSize 3 -Ratio 1 -Data 'empty')
    )

    Invoke-SpectreLive -Data $layout -ScriptBlock {
        param([Spectre.Console.LiveDisplayContext]$LiveContext)

        $headerPanel = Get-XdrLiveHeaderPanel -Context $context -ScriptRoot $PSScriptRoot
        $authAttempted = $false
        $authSucceeded = $false
        $dataLoaded = $false
        $fatalErrorMessage = $null

        $panelOrder = @('incidents', 'incident_details', 'alerts', 'action_status')
        $selectedIncidentDetailsTab = 'details'  # 'details' or 'entities'
        $activePanelIndex = 0
        $activePanel = $panelOrder[$activePanelIndex]
        $context.Selection.Panel = $activePanel

        $selectedIndex = 0
        $selectedAlertIndex = 0
        $selectedEntityIndex = 0
        $selectedActionIndex = 0
        $selectedIncident = $null
        $selectedAlert = $null
        $selectedEntity = $null
        $isQueryMode = $false
        $selectedQueryIndex = 0
        $selectedQuery = $null
        $selectedQueryResult = $null
        $visibleAlerts = @()
        $visibleAlertIncidentId = $null
        $actionEntries = @()
        $pendingConfirmation = $null
        $pendingTextInput = $null
        $pendingIncidentResolution = $null
        $pendingIncidentClassification = $null
        $pendingIncidentComment = $null
        $activePanelBeforeResolution = $null
        $activePanelBeforeClassification = $null
        $activePanelBeforeComment = $null
        $pendingQuitConfirmation = $false
        $showKeyboardHelpOverlay = $false
        $ignoreEnterUntil = [datetime]::MinValue
        $alertsByIncidentId = @{}
        $entitiesByIncidentId = @{}
        $entityAlertCountByIncidentId = @{}
        $selectedAlertIdByIncidentId = @{}
        $alertLoadJobsByIncidentId = @{}
        $entityLoadJobsByIncidentId = @{}
        $alertPreloadQueue = [System.Collections.Queue]::new()
        $maxAlertLoadJobs = 2
        $prefetchCompletedAt = $null
        $modulePath = Join-Path $PSScriptRoot '..' 'PwshXDRSpectre.psm1'
        $triageOptions = Get-XdrTriageOptions
        $autoRefreshInterval = [timespan]::FromMinutes(3)
        $lastDataRefreshAt = $null
        $pendingRefreshIncidentId = $null
        $pendingRefreshAlertId = $null
        $lastHeartbeat = Get-Date
        $heartbeatCounter = 0
        $queryExecutionJob = $null
        $queryResultsByQueryId = @{}

        try {
            $context.Data.QueryCatalog = @(Get-XdrQueryCatalog)
        }
        catch {
            $catalogErrorMessage = "Query catalog load failed: $($_.Exception.Message)"
            $context.Data.QueryCatalog = @()
            $context.Diagnostics.LastError = $_
            $context.Diagnostics.Warnings = @($context.Diagnostics.Warnings + $catalogErrorMessage)
            Set-LiveStatusMessage -Context $context -Message $catalogErrorMessage -Level 'error'
            Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message $catalogErrorMessage
        }

        if (@($context.Data.QueryCatalog).Count -gt 0) {
            $selectedQuery = $context.Data.QueryCatalog[0]
        }

        $syncSelectedQuery = {
            $queryCatalog = @($context.Data.QueryCatalog)
            if ($queryCatalog.Count -eq 0) {
                $selectedQueryIndex = 0
                $selectedQuery = $null
                $selectedQueryResult = $null
                return
            }

            $selectedQueryIndex = [Math]::Min([Math]::Max($selectedQueryIndex, 0), $queryCatalog.Count - 1)
            $selectedQuery = $queryCatalog[$selectedQueryIndex]
            $selectedQueryResult = if ($queryResultsByQueryId.ContainsKey([string]$selectedQuery.id)) { $queryResultsByQueryId[[string]$selectedQuery.id] } else { $null }
        }

        $executeSelectedQuery = {
            if (-not $selectedQuery) {
                Set-LiveStatusMessage -Context $context -Message 'No hunting query is selected.' -Level 'warning'
                return
            }

            if ($queryExecutionJob -and $queryExecutionJob.State -notin @('Completed', 'Failed', 'Stopped')) {
                Set-LiveStatusMessage -Context $context -Message 'A hunting query is already running.' -Level 'warning'
                return
            }

            $queryExecutionJob = Start-XdrLiveQueryJob -Query $selectedQuery -ModulePath $modulePath -Context $context -ExistingJob $queryExecutionJob -LogPath $dashboardLogPath
            if ($queryExecutionJob) {
                Set-LiveStatusMessage -Context $context -Message "Running hunting query: $([string]$selectedQuery.name)" -Level 'info'
            }
            else {
                Set-LiveStatusMessage -Context $context -Message 'Unable to start hunting query job.' -Level 'warning'
            }
        }

        $getQueryContextGuidance = {
            param([string]$ContextKey)

            switch ([string]$ContextKey) {
                'IncidentId' { 'Select an incident in the incident list first.' }
                'DeviceId' { 'Select a device in the incident entities tab first.' }
                'UserId' { 'Select a user in the incident entities tab first. Manual UserId entry is not implemented yet.' }
                'FileHash' { 'Select a file in the incident entities tab first.' }
                default { "Provide required context: $ContextKey" }
            }
        }

        $getIncidentDetailsTabHeader = {
            param([string]$CurrentTab)

            if ([string]$CurrentTab -eq 'entities') {
                return "[grey70 on #1C1C1C]| Incident details |[/][bold black on #C0C0C0]| Entities |[/] [grey](ALT+D to switch)[/]"
            }

            return "[bold black on #C0C0C0]| Incident details |[/][grey70 on #1C1C1C]| Entities |[/] [grey](ALT+E to switch)[/]"
        }

        $resetDashboardDataForRefresh = {
            param(
                [string]$ReasonMessage,
                [bool]$PreserveSelection = $true
            )

            $pendingRefreshIncidentId = if ($PreserveSelection -and $selectedIncident) { [string]$selectedIncident.IncidentId } else { $null }
            $pendingRefreshAlertId = if ($PreserveSelection -and $selectedAlert) { [string]$selectedAlert.AlertId } else { $null }

            Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message "Resetting dashboard data for refresh. PreserveSelection=$PreserveSelection"

            $dataLoaded = $false
            foreach ($jobEntry in @($alertLoadJobsByIncidentId.GetEnumerator())) {
                Stop-Job -Job $jobEntry.Value -ErrorAction SilentlyContinue | Out-Null
                Remove-Job -Job $jobEntry.Value -Force -ErrorAction SilentlyContinue
            }
            foreach ($entityJobEntry in @($entityLoadJobsByIncidentId.GetEnumerator())) {
                Stop-Job -Job $entityJobEntry.Value -ErrorAction SilentlyContinue | Out-Null
                Remove-Job -Job $entityJobEntry.Value -Force -ErrorAction SilentlyContinue
            }
            $alertLoadJobsByIncidentId.Clear()
            $entityLoadJobsByIncidentId.Clear()
            $alertPreloadQueue.Clear()

            if (-not $PreserveSelection) {
                $context.Data.Incidents = @()
                $context.Data.Alerts = @()
                $context.Data.Entities = @()
                $visibleAlerts = @()
                $visibleAlertIncidentId = $null
                $selectedIndex = 0
                $selectedAlertIndex = 0
                $selectedEntityIndex = 0
                $selectedIncident = $null
                $selectedAlert = $null
                $selectedEntity = $null
                $context.Selection.Incident = $null
                $context.Selection.Alert = $null
                $context.Selection.Entity = $null
                $alertsByIncidentId.Clear()
                $entitiesByIncidentId.Clear()
                $entityAlertCountByIncidentId.Clear()
                $selectedAlertIdByIncidentId.Clear()
            }

            if (-not [string]::IsNullOrWhiteSpace($ReasonMessage)) {
                Set-LiveStatusMessage -Context $context -Message $ReasonMessage -Level 'info'
            }

            Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message 'Dashboard data reset completed.'
        }

        $syncVisibleAlertsFromContext = {
            param(
                [ref]$VisibleAlerts,
                [ref]$VisibleAlertIncidentId,
                [object]$Incident
            )

            $VisibleAlerts.Value = @($context.Data.Alerts)
            $VisibleAlertIncidentId.Value = if ($Incident) { [string]$Incident.IncidentId } else { $null }
        }

        $clearVisibleAlerts = {
            param(
                [ref]$VisibleAlerts,
                [ref]$VisibleAlertIncidentId
            )

            $VisibleAlerts.Value = @()
            $VisibleAlertIncidentId.Value = $null
        }

        $syncCachedDataToIncidents = {
            param([object[]]$Incidents)

            $activeIncidentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($incident in @($Incidents)) {
                if (-not $incident) {
                    continue
                }

                $incidentId = [string]$incident.IncidentId
                if ([string]::IsNullOrWhiteSpace($incidentId)) {
                    continue
                }

                [void]$activeIncidentIds.Add($incidentId)
            }

            foreach ($cacheTable in @($alertsByIncidentId, $entitiesByIncidentId, $entityAlertCountByIncidentId, $selectedAlertIdByIncidentId)) {
                foreach ($cacheKey in @($cacheTable.Keys)) {
                    if (-not $activeIncidentIds.Contains([string]$cacheKey)) {
                        $cacheTable.Remove($cacheKey)
                    }
                }
            }
        }

        $startEntityExtraction = {
            param([object]$Incident)

            if (-not $Incident) {
                return
            }

            $incidentId = [string]$Incident.IncidentId
            if ([string]::IsNullOrWhiteSpace($incidentId)) {
                return
            }

            if ($entityLoadJobsByIncidentId.ContainsKey($incidentId)) {
                return
            }

            $alertsForIncident = if ($alertsByIncidentId.ContainsKey($incidentId)) {
                @($alertsByIncidentId[$incidentId])
            }
            else {
                @()
            }

            $jobPayload = [pscustomobject]@{
                ModulePath       = $modulePath
                IncidentData     = $Incident
                AlertData        = @($alertsForIncident)
                DashboardLogPath = $dashboardLogPath
                IncidentId       = $incidentId
            }

            $entityLoadJobsByIncidentId[$incidentId] = Start-ThreadJob -ScriptBlock {
                param([object]$JobPayload)

                Import-Module $JobPayload.ModulePath -Force | Out-Null
                & (Get-Module PwshXDRSpectre) {
                    param(
                        [string]$InnerDashboardLogPath,
                        [string]$InnerIncidentId
                    )

                    Write-XdrLiveDashboardLog -LogPath $InnerDashboardLogPath -Message "Entity extraction job started. IncidentId=$InnerIncidentId"
                } $JobPayload.DashboardLogPath $JobPayload.IncidentId
                & (Get-Module PwshXDRSpectre) {
                    param(
                        [object]$InnerIncidentData,
                        [object[]]$InnerAlertData
                    )

                    Get-XdrIncidentEntities -Incident $InnerIncidentData -Alerts $InnerAlertData
                } $JobPayload.IncidentData @($JobPayload.AlertData)
            } -ArgumentList $jobPayload
        }

        while ($true) {
            # Update heartbeat on every iteration to show dashboard is responsive
            $lastHeartbeat = Get-Date
            $heartbeatCounter++

            $statusExpiresAtProperty = $context.Ui.PSObject.Properties['StatusExpiresAt']
            if ($statusExpiresAtProperty -and $statusExpiresAtProperty.Value -is [datetime]) {
                if ((Get-Date) -ge [datetime]$statusExpiresAtProperty.Value) {
                    $context.Ui.StatusMessage = $null
                    $context.Ui.StatusExpiresAt = $null
                }
            }

            $incidentDetailsHeader = & $getIncidentDetailsTabHeader $selectedIncidentDetailsTab

            if (-not $authAttempted) {
                Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message 'Authentication sequence started.'
                $layout['header'].Update((Get-XdrLiveHeaderPanel -Context $context -ScriptRoot $PSScriptRoot)) | Out-Null
            $layout['incidents'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
            $layout['incident_details'].Update((Format-SpectrePanel -Header $incidentDetailsHeader -Data 'Preparing authentication...' -Expand)) | Out-Null
            $layout['alerts'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alerts' -Title 'Alert List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
            $layout['alert_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
            $layout['action_status'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
            $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -SelectedIncident $selectedIncident -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -LastRefreshAt $lastDataRefreshAt -HeartbeatAt $lastHeartbeat -HeartbeatCounter $heartbeatCounter) -Expand)) | Out-Null
                $LiveContext.Refresh()

                $authAttempted = $true
            $layout['incidents'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Authenticating with Microsoft Graph...' -Expand)) | Out-Null
            $layout['incident_details'].Update((Format-SpectrePanel -Header $incidentDetailsHeader -Data 'Authenticating with Microsoft Graph...' -Expand)) | Out-Null
            $layout['action_status'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Authenticating with Microsoft Graph...' -Expand)) | Out-Null
            $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -SelectedIncident $selectedIncident -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -LastRefreshAt $lastDataRefreshAt -HeartbeatAt $lastHeartbeat -HeartbeatCounter $heartbeatCounter) -Expand)) | Out-Null
                $LiveContext.Refresh()

                $connectResult = Connect-XdrSession -Context $context -UseDeviceCode:$UseDeviceCode.IsPresent
                if (-not $connectResult.Success) {
                    $fatalErrorMessage = $connectResult.Message
                    Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message "Authentication failed: $fatalErrorMessage" -Level 'ERROR'
                }
                else {
                    $authSucceeded = $true
                    Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message 'Authentication succeeded.'
                }

                continue
            }

            if (-not $authSucceeded) {
                $layout['header'].Update((Get-XdrLiveHeaderPanel -Context $context -ScriptRoot $PSScriptRoot)) | Out-Null
                $layout['incidents'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No incidents found. Press Ctrl+C to exit.' -Expand)) | Out-Null
                $layout['incident_details'].Update((Format-SpectrePanel -Header '[red]Authentication Failed[/]' -Data $fatalErrorMessage -Expand)) | Out-Null
                $layout['alerts'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alerts' -Title 'Alert List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No data available.' -Expand)) | Out-Null
                $layout['alert_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No data available.' -Expand)) | Out-Null
                $layout['action_status'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No actions available.' -Expand)) | Out-Null
                $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -SelectedIncident $selectedIncident -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -LastRefreshAt $lastDataRefreshAt -HeartbeatAt $lastHeartbeat -HeartbeatCounter $heartbeatCounter) -Expand)) | Out-Null
                $LiveContext.Refresh()

                $keyOnError = Get-XdrLastKeyPressed
                if ($keyOnError -and $keyOnError.Key -eq 'Escape') {
                    return
                }

                Start-Sleep -Milliseconds $context.Ui.RefreshIntervalMs
                continue
            }

            if (-not $dataLoaded) {
                $hasVisibleIncidentData = @($context.Data.Incidents).Count -gt 0
                Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message 'Loading incidents and initial dashboard data.'
                if (-not $hasVisibleIncidentData) {
                    $layout['header'].Update((Get-XdrLiveHeaderPanel -Context $context -ScriptRoot $PSScriptRoot)) | Out-Null
                    $layout['incidents'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Loading incidents...' -Expand)) | Out-Null
                    $layout['incident_details'].Update((Format-SpectrePanel -Header $incidentDetailsHeader -Data 'Loading incidents...' -Expand)) | Out-Null
                    $layout['action_status'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Loading capabilities...' -Expand)) | Out-Null
                    $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -SelectedIncident $selectedIncident -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -LastRefreshAt $lastDataRefreshAt -HeartbeatAt $lastHeartbeat -HeartbeatCounter $heartbeatCounter) -Expand)) | Out-Null
                    $LiveContext.Refresh()
                }

                $incidentsResult = Get-XdrIncidents -Context $context -Limit $Limit
                if (-not $incidentsResult.Success) {
                    $fatalErrorMessage = $incidentsResult.Message
                    Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message "Initial incident load failed while authentication state was preserved: $fatalErrorMessage" -Level 'ERROR'
                    continue
                }

                $dataLoaded = $true
                $lastDataRefreshAt = Get-Date
                & $syncCachedDataToIncidents $context.Data.Incidents
                Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message "Initial incident load completed. IncidentCount=$(@($context.Data.Incidents).Count)"
                if ($context.Data.Incidents.Count -gt 0) {
                    $selectedIndex = 0
                    if (-not [string]::IsNullOrWhiteSpace([string]$pendingRefreshIncidentId)) {
                        for ($incidentCursor = 0; $incidentCursor -lt $context.Data.Incidents.Count; $incidentCursor++) {
                            if ([string]$context.Data.Incidents[$incidentCursor].IncidentId -eq [string]$pendingRefreshIncidentId) {
                                $selectedIndex = $incidentCursor
                                break
                            }
                        }
                    }
                    $selectedIncident = $context.Data.Incidents[$selectedIndex]
                    $context.Selection.Incident = $selectedIncident
                    $selectedEntityIndex = 0
                    $selectedEntity = $null
                    $context.Selection.Entity = $null
                    if ($entitiesByIncidentId.ContainsKey([string]$selectedIncident.IncidentId)) {
                        $context.Data.Entities = @($entitiesByIncidentId[[string]$selectedIncident.IncidentId])
                    }
                    else {
                        $context.Data.Entities = @()
                    }
                    if (-not [string]::IsNullOrWhiteSpace([string]$pendingRefreshAlertId)) {
                        $selectedAlertIdByIncidentId[[string]$selectedIncident.IncidentId] = [string]$pendingRefreshAlertId
                    }
                    if (-not (Restore-XdrLiveCachedAlertsForIncident -IncidentId ([string]$selectedIncident.IncidentId) -AlertsByIncidentId $alertsByIncidentId -Context $context -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex))) {
                        $selectedAlert = $null
                        $selectedAlertIndex = 0
                        $context.Selection.Alert = $null
                        $context.Data.Alerts = @()
                        & $clearVisibleAlerts ([ref]$visibleAlerts) ([ref]$visibleAlertIncidentId)
                        Start-XdrLiveAlertLoadJob -Incident $selectedIncident -RestoreSelectionOnCompletion -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -LogPath $dashboardLogPath | Out-Null
                    }
                    else {
                        & $syncVisibleAlertsFromContext ([ref]$visibleAlerts) ([ref]$visibleAlertIncidentId) $selectedIncident
                    }
                    & $startEntityExtraction $selectedIncident
                }
                else {
                    $context.Data.Alerts = @()
                    $context.Data.Entities = @()
                    & $clearVisibleAlerts ([ref]$visibleAlerts) ([ref]$visibleAlertIncidentId)
                    $selectedIndex = 0
                    $selectedAlertIndex = 0
                    $selectedEntityIndex = 0
                    $selectedIncident = $null
                    $selectedAlert = $null
                    $selectedEntity = $null
                    $context.Selection.Incident = $null
                    $context.Selection.Alert = $null
                    $context.Selection.Entity = $null
                }
                $pendingRefreshIncidentId = $null
                $pendingRefreshAlertId = $null

                Add-XdrLiveAlertPreloads -Incidents $context.Data.Incidents -AlertPreloadQueue $alertPreloadQueue -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId
                Start-XdrLiveQueuedAlertPreloads -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -MaxAlertLoadJobs $maxAlertLoadJobs -AlertPreloadQueue $alertPreloadQueue -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId -LogPath $dashboardLogPath
                continue
            }

            $autoRefreshBlocked =
                ($null -ne $pendingIncidentResolution) -or
                ($null -ne $pendingIncidentClassification) -or
                ($null -ne $pendingIncidentComment) -or
                ($null -ne $pendingTextInput) -or
                ($null -ne $pendingConfirmation)

            if (-not $autoRefreshBlocked -and $null -ne $lastDataRefreshAt -and (Get-Date) -ge $lastDataRefreshAt.Add($autoRefreshInterval)) {
                Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message "Auto-refresh triggered after $autoRefreshInterval. IncidentCount=$(@($context.Data.Incidents).Count)"
                . $resetDashboardDataForRefresh 'Auto-refreshing incidents and alerts (every 3 minutes)...' $true
                continue
            }

            Invoke-XdrLiveAlertLoadJobProcessing -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertsByIncidentId $alertsByIncidentId -SelectedIncident $selectedIncident -Context $context -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex) -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId)
            Invoke-XdrLiveQueryJobProcessing -QueryJob ([ref]$queryExecutionJob) -QueryResultsByQueryId $queryResultsByQueryId -Context $context -SelectedQuery $selectedQuery -SelectedQueryResult ([ref]$selectedQueryResult)
            Start-XdrLiveQueuedAlertPreloads -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -MaxAlertLoadJobs $maxAlertLoadJobs -AlertPreloadQueue $alertPreloadQueue -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId -LogPath $dashboardLogPath

            foreach ($entityJobEntry in @($entityLoadJobsByIncidentId.GetEnumerator())) {
                $incidentIdKey = [string]$entityJobEntry.Key
                $entityJob = $entityJobEntry.Value
                if (-not $entityJob) {
                    $entityLoadJobsByIncidentId.Remove($incidentIdKey)
                    continue
                }

                if ($entityJob.State -eq 'Completed') {
                    $entityResult = Receive-Job -Job $entityJob -ErrorAction SilentlyContinue
                    $entitiesByIncidentId[$incidentIdKey] = @($entityResult)
                    $entityAlertCountByIncidentId[$incidentIdKey] = if ($alertsByIncidentId.ContainsKey($incidentIdKey)) { @($alertsByIncidentId[$incidentIdKey]).Count } else { 0 }
                    Remove-Job -Job $entityJob -Force -ErrorAction SilentlyContinue
                    $entityLoadJobsByIncidentId.Remove($incidentIdKey)
                }
                elseif ($entityJob.State -in @('Failed', 'Stopped')) {
                    $entityError = Receive-Job -Job $entityJob -ErrorAction SilentlyContinue
                    if ($entityError) {
                        $context.Diagnostics.Warnings += @("Entity extraction failed for incident $incidentIdKey.")
                    }

                    Remove-Job -Job $entityJob -Force -ErrorAction SilentlyContinue
                    $entityLoadJobsByIncidentId.Remove($incidentIdKey)
                }
            }

            if ($entityLoadJobsByIncidentId.Count -gt 0 -or $alertLoadJobsByIncidentId.Count -gt 0) {
                Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message "Background jobs active. AlertJobs=$($alertLoadJobsByIncidentId.Count) EntityJobs=$($entityLoadJobsByIncidentId.Count)"
            }

            if ($selectedIncident) {
                $selectedIncidentId = [string]$selectedIncident.IncidentId
                $selectedIncidentAlertCount = if ($alertsByIncidentId.ContainsKey($selectedIncidentId)) { @($alertsByIncidentId[$selectedIncidentId]).Count } else { 0 }

                if ($entitiesByIncidentId.ContainsKey($selectedIncidentId)) {
                    $context.Data.Entities = @($entitiesByIncidentId[$selectedIncidentId])
                }
                else {
                    $context.Data.Entities = @()
                }

                $cachedAlertCount = if ($entityAlertCountByIncidentId.ContainsKey($selectedIncidentId)) { [int]$entityAlertCountByIncidentId[$selectedIncidentId] } else { -1 }
                if ($cachedAlertCount -ne $selectedIncidentAlertCount -and -not $entityLoadJobsByIncidentId.ContainsKey($selectedIncidentId)) {
                    & $startEntityExtraction $selectedIncident
                }
            }

            if ($null -ne $pendingIncidentResolution) {
                $activePanel = 'action_status'
                $activePanelIndex = [array]::IndexOf($panelOrder, 'action_status')
                $context.Selection.Panel = $activePanel
            }
            elseif ($null -ne $pendingIncidentClassification) {
                $activePanel = 'action_status'
                $activePanelIndex = [array]::IndexOf($panelOrder, 'action_status')
                $context.Selection.Panel = $activePanel
            }
            elseif ($null -ne $pendingIncidentComment) {
                $activePanel = 'action_status'
                $activePanelIndex = [array]::IndexOf($panelOrder, 'action_status')
                $context.Selection.Panel = $activePanel
            }

            # Capture all buffered keys for text entry and hunting mode so rapid input
            # does not collapse into a single last-read keypress.
            $keys = if (
                $isQueryMode -or
                $null -ne $pendingTextInput -or
                ($null -ne $pendingIncidentComment -and [string]$pendingIncidentComment.Step -eq 'comment') -or
                ($null -ne $pendingIncidentResolution -and [string]$pendingIncidentResolution.Step -eq 'comment')
            ) {
                @(Get-XdrAllKeysPressed)
            } else {
                $key = Get-XdrLastKeyPressed
                if ($null -ne $key) { @($key) } else { @() }
            }

            foreach ($key in $keys) {
                if ($null -eq $key) { continue }
                
                $currentInputTime = Get-Date
                $keyHandled = $false
                $keyChar = ([string]$key.KeyChar).ToLowerInvariant()
                $isShiftPressed = (($key.Modifiers -band [ConsoleModifiers]::Shift) -ne 0)
                $isCtrlPressed = (($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0)
                $isAltPressed = (($key.Modifiers -band [ConsoleModifiers]::Alt) -ne 0)
                $modifierLabels = @()
                if ($isCtrlPressed) { $modifierLabels += 'Ctrl' }
                if ($isAltPressed) { $modifierLabels += 'Alt' }
                if ($isShiftPressed) { $modifierLabels += 'Shift' }
                $modifierSummary = if ($modifierLabels.Count -gt 0) { $modifierLabels -join '+' } else { 'None' }
                $keyCharDisplay = if ([char]$key.KeyChar -eq [char]0) { '' } else { [string]$key.KeyChar }
                $context.Diagnostics.LastInput = [pscustomobject][ordered]@{
                    Timestamp          = $currentInputTime
                    Key                = [string]$key.Key
                    KeyChar            = $keyCharDisplay
                    Modifiers          = $modifierSummary
                    ActivePanel        = [string]$activePanel
                    IsQueryMode        = [bool]$isQueryMode
                    SelectedQueryIndex = [int]$selectedQueryIndex
                    SelectedQueryId    = $(if ($selectedQuery) { [string]$selectedQuery.id } else { '' })
                    SelectedEntity     = $(if ($selectedEntity) { [string]$selectedEntity.DisplayName } else { '' })
                }
                if ($context.Diagnostics.InputDebugEnabled -and $isQueryMode) {
                    Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message "InputDebug Key=$([string]$key.Key) Char=$keyCharDisplay Modifiers=$modifierSummary Panel=$activePanel QueryMode=$isQueryMode QueryIndex=$selectedQueryIndex QueryId=$(if ($selectedQuery) { [string]$selectedQuery.id } else { '' }) Entity=$(if ($selectedEntity) { [string]$selectedEntity.DisplayName } else { '' })"
                }

                if (
                    $key.Key -eq 'Enter' -and
                    $currentInputTime -lt $ignoreEnterUntil -and
                    $null -eq $pendingIncidentResolution -and
                    $null -eq $pendingIncidentClassification -and
                    $null -eq $pendingIncidentComment -and
                    $null -eq $pendingTextInput -and
                    -not $pendingConfirmation
                ) {
                    continue
                }

                if ($pendingQuitConfirmation) {
                    $keyHandled = $true
                    if ((-not $isAltPressed -and -not $isCtrlPressed -and $keyChar -eq 'y') -or $key.Key -eq 'Enter') {
                        return
                    }

                    if ((-not $isAltPressed -and -not $isCtrlPressed -and $keyChar -eq 'n') -or $key.Key -eq 'Escape') {
                        $pendingQuitConfirmation = $false
                        Set-LiveStatusMessage -Context $context -Message 'Quit canceled.' -Level 'info'
                    }
                }
                elseif ($null -ne $pendingIncidentResolution) {
                    $keyHandled = $true
                    if ($key.Key -eq 'Escape') {
                        $pendingIncidentResolution = $null
                        if (-not [string]::IsNullOrWhiteSpace([string]$activePanelBeforeResolution)) {
                            $activePanel = [string]$activePanelBeforeResolution
                            $activePanelIndex = [array]::IndexOf($panelOrder, $activePanel)
                            if ($activePanelIndex -lt 0) {
                                $activePanelIndex = 0
                                $activePanel = $panelOrder[$activePanelIndex]
                            }
                            $context.Selection.Panel = $activePanel
                        }
                        $activePanelBeforeResolution = $null
                        Set-LiveStatusMessage -Context $context -Message 'Incident resolution canceled.' -Level 'warning'
                    }
                    else {
                        $currentResolutionStep = [string]$pendingIncidentResolution.Step

                        if ($key.Key -eq 'PageDown') {
                            if ($currentResolutionStep -eq 'classification') {
                                $pendingIncidentResolution.Step = 'determination'
                            }
                            elseif ($currentResolutionStep -eq 'determination') {
                                $pendingIncidentResolution.Step = 'comment'
                            }
                            elseif ($currentResolutionStep -eq 'comment') {
                                $pendingIncidentResolution.Step = 'confirm'
                            }
                        }
                        elseif ($key.Key -eq 'PageUp') {
                            if ($currentResolutionStep -eq 'confirm') {
                                $pendingIncidentResolution.Step = 'comment'
                            }
                            elseif ($currentResolutionStep -eq 'comment') {
                                $pendingIncidentResolution.Step = 'determination'
                            }
                            elseif ($currentResolutionStep -eq 'determination') {
                                $pendingIncidentResolution.Step = 'classification'
                            }
                        }

                        switch ($currentResolutionStep) {
                            'classification' {
                                $optionCount = @($pendingIncidentResolution.ClassificationOptions).Count
                                if ($optionCount -gt 0 -and $key.Key -eq 'DownArrow') {
                                    $pendingIncidentResolution.ClassificationIndex = ($pendingIncidentResolution.ClassificationIndex + 1) % $optionCount
                                }
                                elseif ($optionCount -gt 0 -and $key.Key -eq 'UpArrow') {
                                    $pendingIncidentResolution.ClassificationIndex = ($pendingIncidentResolution.ClassificationIndex - 1 + $optionCount) % $optionCount
                                }
                                elseif ($key.Key -eq 'Enter') {
                                    $pendingIncidentResolution.Step = 'determination'
                                }
                            }
                            'determination' {
                                $optionCount = @($pendingIncidentResolution.DeterminationOptions).Count
                                if ($optionCount -gt 0 -and $key.Key -eq 'DownArrow') {
                                    $pendingIncidentResolution.DeterminationIndex = ($pendingIncidentResolution.DeterminationIndex + 1) % $optionCount
                                }
                                elseif ($optionCount -gt 0 -and $key.Key -eq 'UpArrow') {
                                    $pendingIncidentResolution.DeterminationIndex = ($pendingIncidentResolution.DeterminationIndex - 1 + $optionCount) % $optionCount
                                }
                                elseif ($key.Key -eq 'Enter') {
                                    $pendingIncidentResolution.Step = 'comment'
                                }
                            }
                            'comment' {
                                if ($key.Key -eq 'Enter') {
                                    $pendingIncidentResolution.Step = 'confirm'
                                }
                                elseif ($key.Key -eq 'Backspace') {
                                        if (-not [string]::IsNullOrEmpty([string]$pendingIncidentResolution.ResolvingComment)) {
                                            $pendingIncidentResolution.ResolvingComment = [string]$pendingIncidentResolution.ResolvingComment.Substring(0, [string]$pendingIncidentResolution.ResolvingComment.Length - 1)
                                    }
                                }
                                elseif ($key.KeyChar -and -not [char]::IsControl($key.KeyChar) -and -not $isAltPressed -and -not $isCtrlPressed) {
                                        $pendingIncidentResolution.ResolvingComment = ([string]$pendingIncidentResolution.ResolvingComment) + [string]$key.KeyChar
                                }
                            }
                            'confirm' {
                                if (-not $isAltPressed -and -not $isCtrlPressed -and $keyChar -eq 'n') {
                                    $pendingIncidentResolution.Step = 'comment'
                                }
                                elseif ((-not $isAltPressed -and -not $isCtrlPressed -and $keyChar -eq 'y') -or $key.Key -eq 'Enter') {
                                    $selectedClassificationOption = $pendingIncidentResolution.ClassificationOptions[$pendingIncidentResolution.ClassificationIndex]
                                    $selectedClassificationLabel = [string]$selectedClassificationOption.label
                                    $selectedDeterminationOption = $pendingIncidentResolution.DeterminationOptions[$pendingIncidentResolution.DeterminationIndex]
                                    $selectedDeterminationLabel = [string]$selectedDeterminationOption.label
                                        $commentText = if ([string]::IsNullOrWhiteSpace([string]$pendingIncidentResolution.ResolvingComment)) { $null } else { [string]$pendingIncidentResolution.ResolvingComment }

                                    $resolveResult = Set-XdrIncidentTriage -Context $context -IncidentId $selectedIncident.IncidentId -Status 'Resolved' -Classification $selectedClassificationLabel -Determination $selectedDeterminationLabel -Comment $commentText -SkipConfirmation
                                    Set-StatusFromResult -Context $context -Result $resolveResult
                                    $pendingIncidentResolution = $null
                                    $ignoreEnterUntil = (Get-Date).AddMilliseconds(300)
                                    if (-not [string]::IsNullOrWhiteSpace([string]$activePanelBeforeResolution)) {
                                        $activePanel = [string]$activePanelBeforeResolution
                                        $activePanelIndex = [array]::IndexOf($panelOrder, $activePanel)
                                        if ($activePanelIndex -lt 0) {
                                            $activePanelIndex = 0
                                            $activePanel = $panelOrder[$activePanelIndex]
                                        }
                                        $context.Selection.Panel = $activePanel
                                    }
                                    $activePanelBeforeResolution = $null
                                }
                            }
                        }
                    }
                }
                elseif ($null -ne $pendingIncidentClassification) {
                    $keyHandled = $true
                    if ($key.Key -eq 'Escape') {
                        $pendingIncidentClassification = $null
                        if (-not [string]::IsNullOrWhiteSpace([string]$activePanelBeforeClassification)) {
                            $activePanel = [string]$activePanelBeforeClassification
                            $activePanelIndex = [array]::IndexOf($panelOrder, $activePanel)
                            if ($activePanelIndex -lt 0) {
                                $activePanelIndex = 0
                                $activePanel = $panelOrder[$activePanelIndex]
                            }
                            $context.Selection.Panel = $activePanel
                        }
                        $activePanelBeforeClassification = $null
                        Set-LiveStatusMessage -Context $context -Message 'Incident classification picker canceled.' -Level 'warning'
                    }
                    else {
                        $currentClassificationStep = [string]$pendingIncidentClassification.Step
                        if ([string]::IsNullOrWhiteSpace($currentClassificationStep)) {
                            $currentClassificationStep = 'classification'
                            $pendingIncidentClassification.Step = $currentClassificationStep
                        }

                        $optionCount = @($pendingIncidentClassification.ClassificationOptions).Count

                        if ($currentClassificationStep -eq 'classification') {
                            if ($optionCount -gt 0 -and $key.Key -eq 'DownArrow') {
                                $pendingIncidentClassification.ClassificationIndex = ($pendingIncidentClassification.ClassificationIndex + 1) % $optionCount
                            }
                            elseif ($optionCount -gt 0 -and $key.Key -eq 'UpArrow') {
                                $pendingIncidentClassification.ClassificationIndex = ($pendingIncidentClassification.ClassificationIndex - 1 + $optionCount) % $optionCount
                            }
                            elseif ($key.Key -eq 'Enter' -or $key.Key -eq 'PageDown') {
                                $pendingIncidentClassification.Step = 'confirm'
                            }
                        }
                        elseif ($currentClassificationStep -eq 'confirm') {
                            if ($key.Key -eq 'PageUp' -or (-not $isAltPressed -and -not $isCtrlPressed -and $keyChar -eq 'n')) {
                                $pendingIncidentClassification.Step = 'classification'
                            }
                            elseif ((-not $isAltPressed -and -not $isCtrlPressed -and $keyChar -eq 'y') -or $key.Key -eq 'Enter') {
                                $selectedClassificationOption = $pendingIncidentClassification.ClassificationOptions[$pendingIncidentClassification.ClassificationIndex]
                                $selectedClassificationLabel = [string]$selectedClassificationOption.label

                                $classificationResult = Set-XdrIncidentTriage -Context $context -IncidentId $selectedIncident.IncidentId -Classification $selectedClassificationLabel
                                Set-StatusFromResult -Context $context -Result $classificationResult

                                $pendingIncidentClassification = $null
                                if (-not [string]::IsNullOrWhiteSpace([string]$activePanelBeforeClassification)) {
                                    $activePanel = [string]$activePanelBeforeClassification
                                    $activePanelIndex = [array]::IndexOf($panelOrder, $activePanel)
                                    if ($activePanelIndex -lt 0) {
                                        $activePanelIndex = 0
                                        $activePanel = $panelOrder[$activePanelIndex]
                                    }
                                    $context.Selection.Panel = $activePanel
                                }
                                $activePanelBeforeClassification = $null
                                $ignoreEnterUntil = (Get-Date).AddMilliseconds(300)
                            }
                        }
                    }
                }
                elseif ($null -ne $pendingIncidentComment) {
                    $keyHandled = $true
                    if ($key.Key -eq 'Escape') {
                        $pendingIncidentComment = $null
                        if (-not [string]::IsNullOrWhiteSpace([string]$activePanelBeforeComment)) {
                            $activePanel = [string]$activePanelBeforeComment
                            $activePanelIndex = [array]::IndexOf($panelOrder, $activePanel)
                            if ($activePanelIndex -lt 0) {
                                $activePanelIndex = 0
                                $activePanel = $panelOrder[$activePanelIndex]
                            }
                            $context.Selection.Panel = $activePanel
                        }
                        $activePanelBeforeComment = $null
                        Set-LiveStatusMessage -Context $context -Message 'Incident comment wizard canceled.' -Level 'warning'
                    }
                    else {
                        $currentCommentStep = [string]$pendingIncidentComment.Step
                        if ([string]::IsNullOrWhiteSpace($currentCommentStep)) {
                            $currentCommentStep = 'comment'
                            $pendingIncidentComment.Step = $currentCommentStep
                        }

                        if ($currentCommentStep -eq 'comment') {
                            if ($key.Key -eq 'Enter' -or $key.Key -eq 'PageDown') {
                                if ([string]::IsNullOrWhiteSpace([string]$pendingIncidentComment.Comment)) {
                                    Set-LiveStatusMessage -Context $context -Message 'Comment cannot be empty.' -Level 'warning'
                                }
                                else {
                                    $pendingIncidentComment.Step = 'confirm'
                                }
                            }
                            elseif ($key.Key -eq 'Backspace') {
                                if (-not [string]::IsNullOrEmpty([string]$pendingIncidentComment.Comment)) {
                                    $pendingIncidentComment.Comment = [string]$pendingIncidentComment.Comment.Substring(0, [string]$pendingIncidentComment.Comment.Length - 1)
                                }
                            }
                            elseif ($key.KeyChar -and -not [char]::IsControl($key.KeyChar) -and -not $isAltPressed -and -not $isCtrlPressed) {
                                $pendingIncidentComment.Comment = ([string]$pendingIncidentComment.Comment) + [string]$key.KeyChar
                            }
                        }
                        elseif ($currentCommentStep -eq 'confirm') {
                            if ($key.Key -eq 'PageUp' -or (-not $isAltPressed -and -not $isCtrlPressed -and $keyChar -eq 'n')) {
                                $pendingIncidentComment.Step = 'comment'
                            }
                            elseif ((-not $isAltPressed -and -not $isCtrlPressed -and $keyChar -eq 'y') -or $key.Key -eq 'Enter') {
                                $commentText = [string]$pendingIncidentComment.Comment
                                if ([string]::IsNullOrWhiteSpace($commentText)) {
                                    Set-LiveStatusMessage -Context $context -Message 'Comment cannot be empty.' -Level 'warning'
                                    $pendingIncidentComment.Step = 'comment'
                                }
                                else {
                                    $commentResult = Set-XdrIncidentTriage -Context $context -IncidentId $selectedIncident.IncidentId -Comment $commentText
                                    Set-StatusFromResult -Context $context -Result $commentResult
                                    $pendingIncidentComment = $null
                                    $ignoreEnterUntil = (Get-Date).AddMilliseconds(300)
                                    if (-not [string]::IsNullOrWhiteSpace([string]$activePanelBeforeComment)) {
                                        $activePanel = [string]$activePanelBeforeComment
                                        $activePanelIndex = [array]::IndexOf($panelOrder, $activePanel)
                                        if ($activePanelIndex -lt 0) {
                                            $activePanelIndex = 0
                                            $activePanel = $panelOrder[$activePanelIndex]
                                        }
                                        $context.Selection.Panel = $activePanel
                                    }
                                    $activePanelBeforeComment = $null
                                }
                            }
                        }
                    }
                }
                elseif ($null -ne $pendingTextInput) {
                    $keyHandled = $true
                    if ($key.Key -eq 'Escape') {
                        $pendingTextInput = $null
                        Set-LiveStatusMessage -Context $context -Message 'Comment entry canceled.' -Level 'warning'
                    }
                    elseif ($key.Key -eq 'Enter') {
                        $submitHandler = $pendingTextInput.Submit
                        $submittedText = [string]$pendingTextInput.Value
                        $pendingTextInput = $null
                        & $submitHandler $submittedText
                    }
                    elseif ($key.Key -eq 'Backspace') {
                        if (-not [string]::IsNullOrEmpty([string]$pendingTextInput.Value)) {
                            $pendingTextInput.Value = [string]$pendingTextInput.Value.Substring(0, [string]$pendingTextInput.Value.Length - 1)
                        }
                    }
                    elseif ($key.KeyChar -and -not [char]::IsControl($key.KeyChar) -and -not $isAltPressed -and -not $isCtrlPressed) {
                        $pendingTextInput.Value = ([string]$pendingTextInput.Value) + [string]$key.KeyChar
                    }
                }
                elseif ($pendingConfirmation) {
                    $keyHandled = $true
                    if (-not $isAltPressed -and -not $isCtrlPressed -and $keyChar -eq 'y') {
                        $confirmedResult = & $pendingConfirmation.Execute
                        Set-StatusFromResult -Context $context -Result $confirmedResult
                        $pendingConfirmation = $null
                    }
                    elseif ($key.Key -eq 'Enter') {
                        $confirmedResult = & $pendingConfirmation.Execute
                        Set-StatusFromResult -Context $context -Result $confirmedResult
                        $pendingConfirmation = $null
                        $ignoreEnterUntil = (Get-Date).AddMilliseconds(300)
                    }
                    elseif ((-not $isAltPressed -and -not $isCtrlPressed -and $keyChar -eq 'n') -or $key.Key -eq 'Escape') {
                        $pendingConfirmation = $null
                        Set-LiveStatusMessage -Context $context -Message 'Action canceled.' -Level 'warning'
                    }
                }
                elseif ($key.Key -eq 'F1') {
                    $keyHandled = $true
                    $showKeyboardHelpOverlay = -not $showKeyboardHelpOverlay
                    if ($showKeyboardHelpOverlay) {
                        Set-LiveStatusMessage -Context $context -Message 'Keyboard help overlay enabled (F1 to close).' -Level 'info'
                    }
                    else {
                        Set-LiveStatusMessage -Context $context -Message 'Keyboard help overlay closed.' -Level 'info'
                    }
                }
                elseif ($isAltPressed -and $keyChar -eq 'k') {
                    $keyHandled = $true
                    $context.Diagnostics.InputDebugEnabled = -not $context.Diagnostics.InputDebugEnabled
                    if ($context.Diagnostics.InputDebugEnabled) {
                        Set-LiveStatusMessage -Context $context -Message 'Input debug enabled. Check the help panel for last key and query state.' -Level 'info'
                    }
                    else {
                        Set-LiveStatusMessage -Context $context -Message 'Input debug disabled.' -Level 'info'
                    }
                }
                elseif ((-not $isAltPressed -and -not $isCtrlPressed -and $keyChar -eq 'q') -or ($isCtrlPressed -and -not $isAltPressed -and $keyChar -eq 'q')) {
                    $keyHandled = $true
                    $pendingQuitConfirmation = $true
                    Set-LiveStatusMessage -Context $context -Message 'Quit dashboard? Press Y to confirm, N or Esc to continue.' -Level 'warning'
                }
                elseif ($isAltPressed -and $keyChar -eq 'e') {
                    if ($selectedIncident) {
                        $selectedIncidentDetailsTab = 'entities'
                        $activePanel = 'incident_details'
                        $activePanelIndex = [array]::IndexOf($panelOrder, 'incident_details')
                        $context.Selection.Panel = $activePanel
                        Set-LiveStatusMessage -Context $context -Message 'Showing related entities panel. Use ↑↓ to navigate, Tab to switch tabs.' -Level 'info'
                    }
                }
                elseif ($isAltPressed -and $keyChar -eq 'd') {
                    if ($selectedIncident) {
                        $selectedIncidentDetailsTab = 'details'
                        $activePanel = 'incident_details'
                        $activePanelIndex = [array]::IndexOf($panelOrder, 'incident_details')
                        $context.Selection.Panel = $activePanel
                        Set-LiveStatusMessage -Context $context -Message 'Showing incident details panel. Use Tab to switch tabs.' -Level 'info'
                    }
                }
                elseif ($isAltPressed -and $keyChar -eq 'h') {
                    $keyHandled = $true
                    $isQueryMode = -not $isQueryMode
                    $activePanel = 'incidents'
                    $activePanelIndex = [array]::IndexOf($panelOrder, 'incidents')
                    $context.Selection.Panel = $activePanel
                    $selectedActionIndex = 0

                    if ($isQueryMode) {
                        . $syncSelectedQuery
                        Set-LiveStatusMessage -Context $context -Message 'Hunting mode enabled. Use the query catalog on the left and Alt+X to execute.' -Level 'info'
                    }
                    else {
                        Set-LiveStatusMessage -Context $context -Message 'Returned to incident workflow.' -Level 'info'
                    }
                }
                elseif ($isQueryMode -and $isAltPressed -and $keyChar -eq 'x') {
                    $keyHandled = $true
                    . $executeSelectedQuery
                }
                elseif ($key.Key -eq 'PageUp') {
                    $activePanelIndex = ($activePanelIndex - 1 + $panelOrder.Count) % $panelOrder.Count
                    $activePanel = $panelOrder[$activePanelIndex]
                    $context.Selection.Panel = $activePanel
                }
                elseif ($key.Key -eq 'PageDown') {
                    $activePanelIndex = ($activePanelIndex + 1) % $panelOrder.Count
                    $activePanel = $panelOrder[$activePanelIndex]
                    $context.Selection.Panel = $activePanel
                }
                elseif ($key.Key -eq 'Tab') {
                    # If in incident_details panel, switch between details and entities tabs
                    if ($activePanel -eq 'incident_details' -and $selectedIncident) {
                        $selectedIncidentDetailsTab = if ($selectedIncidentDetailsTab -eq 'details') { 'entities' } else { 'details' }
                    }
                    else {
                        # Normal panel navigation
                        if ($isShiftPressed) {
                            $activePanelIndex = ($activePanelIndex - 1 + $panelOrder.Count) % $panelOrder.Count
                        }
                        else {
                            $activePanelIndex = ($activePanelIndex + 1) % $panelOrder.Count
                        }
                        $activePanel = $panelOrder[$activePanelIndex]
                        $context.Selection.Panel = $activePanel
                    }
                }
                elseif ($key.Key -eq 'F5' -or (-not $isAltPressed -and -not $isCtrlPressed -and $keyChar -eq 'r')) {
                    . $resetDashboardDataForRefresh 'Refreshing incidents and alert cache...' $true
                    continue
                }

                if ($keyHandled) {
                    # Modal workflows consume the current keypress so it cannot also trigger
                    # normal panel actions later in the same loop iteration.
                }

                elseif (-not $selectedIncident -and -not $isQueryMode) {
                    continue
                }

                elseif ($isQueryMode -and $key.Key -eq 'DownArrow' -and $context.Data.QueryCatalog.Count -gt 0 -and $activePanel -ne 'action_status') {
                    $keyHandled = $true
                    $activePanel = 'incidents'
                    $activePanelIndex = [array]::IndexOf($panelOrder, 'incidents')
                    $context.Selection.Panel = $activePanel
                    $selectedQueryIndex = ($selectedQueryIndex + 1) % $context.Data.QueryCatalog.Count
                    . $syncSelectedQuery
                    Set-LiveStatusMessage -Context $context -Message "Selected hunting query: $([string]$selectedQuery.name)" -Level 'info'
                }
                elseif ($isQueryMode -and $key.Key -eq 'UpArrow' -and $context.Data.QueryCatalog.Count -gt 0 -and $activePanel -ne 'action_status') {
                    $keyHandled = $true
                    $activePanel = 'incidents'
                    $activePanelIndex = [array]::IndexOf($panelOrder, 'incidents')
                    $context.Selection.Panel = $activePanel
                    $selectedQueryIndex = ($selectedQueryIndex - 1 + $context.Data.QueryCatalog.Count) % $context.Data.QueryCatalog.Count
                    . $syncSelectedQuery
                    Set-LiveStatusMessage -Context $context -Message "Selected hunting query: $([string]$selectedQuery.name)" -Level 'info'
                }
                elseif ($isQueryMode -and $key.Key -eq 'Enter' -and $activePanel -eq 'incidents') {
                    $keyHandled = $true
                    . $executeSelectedQuery
                }

                elseif ($key.Key -eq 'DownArrow' -and $activePanel -eq 'incidents') {
                    $selectedIndex = ($selectedIndex + 1) % $context.Data.Incidents.Count
                    $selectedIncident = $context.Data.Incidents[$selectedIndex]
                    $context.Selection.Incident = $selectedIncident
                    $selectedEntityIndex = 0
                    $selectedEntity = $null
                    $context.Selection.Entity = $null
                    $incidentId = [string]$selectedIncident.IncidentId
                    if (-not (Restore-XdrLiveCachedAlertsForIncident -IncidentId $incidentId -AlertsByIncidentId $alertsByIncidentId -Context $context -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex))) {
                        $selectedAlert = $null
                        $selectedAlertIndex = 0
                        $context.Selection.Alert = $null
                        $context.Data.Alerts = @()
                        & $clearVisibleAlerts ([ref]$visibleAlerts) ([ref]$visibleAlertIncidentId)
                        Start-XdrLiveAlertLoadJob -Incident $selectedIncident -RestoreSelectionOnCompletion -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId | Out-Null
                    }
                    else {
                        & $syncVisibleAlertsFromContext ([ref]$visibleAlerts) ([ref]$visibleAlertIncidentId) $selectedIncident
                    }

                    if ($entitiesByIncidentId.ContainsKey($incidentId)) {
                        $context.Data.Entities = @($entitiesByIncidentId[$incidentId])
                    }
                    else {
                        $context.Data.Entities = @()
                    }
                    & $startEntityExtraction $selectedIncident
                }
                elseif ($key.Key -eq 'UpArrow' -and $activePanel -eq 'incidents') {
                    $selectedIndex = ($selectedIndex - 1 + $context.Data.Incidents.Count) % $context.Data.Incidents.Count
                    $selectedIncident = $context.Data.Incidents[$selectedIndex]
                    $context.Selection.Incident = $selectedIncident
                    $selectedEntityIndex = 0
                    $selectedEntity = $null
                    $context.Selection.Entity = $null
                    $incidentId = [string]$selectedIncident.IncidentId
                    if (-not (Restore-XdrLiveCachedAlertsForIncident -IncidentId $incidentId -AlertsByIncidentId $alertsByIncidentId -Context $context -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex))) {
                        $selectedAlert = $null
                        $selectedAlertIndex = 0
                        $context.Selection.Alert = $null
                        $context.Data.Alerts = @()
                        & $clearVisibleAlerts ([ref]$visibleAlerts) ([ref]$visibleAlertIncidentId)
                        Start-XdrLiveAlertLoadJob -Incident $selectedIncident -RestoreSelectionOnCompletion -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId | Out-Null
                    }
                    else {
                        & $syncVisibleAlertsFromContext ([ref]$visibleAlerts) ([ref]$visibleAlertIncidentId) $selectedIncident
                    }

                    if ($entitiesByIncidentId.ContainsKey($incidentId)) {
                        $context.Data.Entities = @($entitiesByIncidentId[$incidentId])
                    }
                    else {
                        $context.Data.Entities = @()
                    }
                    & $startEntityExtraction $selectedIncident
                }
                elseif ($key.Key -eq 'DownArrow' -and $activePanel -eq 'alerts' -and $visibleAlerts.Count -gt 0) {
                    $selectedAlertIndex = ($selectedAlertIndex + 1) % $visibleAlerts.Count
                    $selectedAlert = $visibleAlerts[$selectedAlertIndex]
                    $context.Selection.Alert = $selectedAlert
                    $selectedAlertIdByIncidentId[[string]$selectedIncident.IncidentId] = [string]$selectedAlert.AlertId
                }
                elseif ($key.Key -eq 'UpArrow' -and $activePanel -eq 'alerts' -and $visibleAlerts.Count -gt 0) {
                    $selectedAlertIndex = ($selectedAlertIndex - 1 + $visibleAlerts.Count) % $visibleAlerts.Count
                    $selectedAlert = $visibleAlerts[$selectedAlertIndex]
                    $context.Selection.Alert = $selectedAlert
                    $selectedAlertIdByIncidentId[[string]$selectedIncident.IncidentId] = [string]$selectedAlert.AlertId
                }
                elseif ($selectedIncidentDetailsTab -eq 'entities' -and $key.Key -eq 'DownArrow' -and $activePanel -eq 'incident_details' -and $context.Data.Entities.Count -gt 0) {
                    $selectedEntityIndex = ($selectedEntityIndex + 1) % $context.Data.Entities.Count
                    $selectedEntity = $context.Data.Entities[$selectedEntityIndex]
                    $context.Selection.Entity = $selectedEntity
                }
                elseif ($selectedIncidentDetailsTab -eq 'entities' -and $key.Key -eq 'UpArrow' -and $activePanel -eq 'incident_details' -and $context.Data.Entities.Count -gt 0) {
                    $selectedEntityIndex = ($selectedEntityIndex - 1 + $context.Data.Entities.Count) % $context.Data.Entities.Count
                    $selectedEntity = $context.Data.Entities[$selectedEntityIndex]
                    $context.Selection.Entity = $selectedEntity
                }
                elseif ($selectedIncidentDetailsTab -eq 'entities' -and $key.Key -eq 'Enter' -and $activePanel -eq 'incident_details' -and $selectedEntity) {
                    $keyHandled = $true
                    $isQueryMode = $true
                    $activePanel = 'incidents'
                    $activePanelIndex = [array]::IndexOf($panelOrder, 'incidents')
                    $context.Selection.Panel = $activePanel
                    $selectedActionIndex = 0
                    . $syncSelectedQuery

                    $selectedEntityTypeLabel = [string]$selectedEntity.EntityType
                    $selectedEntityLabel = [string]$selectedEntity.DisplayName
                    Set-LiveStatusMessage -Context $context -Message "Hunting mode enabled for ${selectedEntityTypeLabel}: $selectedEntityLabel" -Level 'info'
                }
                elseif ($key.Key -eq 'DownArrow' -and $activePanel -eq 'action_status' -and $actionEntries.Count -gt 0) {
                    $selectedActionIndex = ($selectedActionIndex + 1) % $actionEntries.Count
                }
                elseif ($key.Key -eq 'UpArrow' -and $activePanel -eq 'action_status' -and $actionEntries.Count -gt 0) {
                    $selectedActionIndex = ($selectedActionIndex - 1 + $actionEntries.Count) % $actionEntries.Count
                }
                elseif ($key.Key -eq 'Enter' -and $activePanel -in @('incidents', 'incident_details')) {
                    if ($selectedIncident) {
                        $incidentId = [string]$selectedIncident.IncidentId
                        if (-not (Restore-XdrLiveCachedAlertsForIncident -IncidentId $incidentId -AlertsByIncidentId $alertsByIncidentId -Context $context -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex))) {
                            if (Start-XdrLiveAlertLoadJob -Incident $selectedIncident -RestoreSelectionOnCompletion -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId) {
                                Set-LiveStatusMessage -Context $context -Message 'Loading alerts in background...' -Level 'info'
                            }
                        }
                        else {
                            & $syncVisibleAlertsFromContext ([ref]$visibleAlerts) ([ref]$visibleAlertIncidentId) $selectedIncident
                        }
                    }
                    if ($visibleAlerts.Count -gt 0) {
                        $activePanel = 'alerts'
                        $activePanelIndex = [array]::IndexOf($panelOrder, 'alerts')
                        $context.Selection.Panel = $activePanel
                    }
                }
                elseif ($key.Key -eq 'Enter' -and $activePanel -eq 'action_status' -and $actionEntries.Count -gt 0) {
                    $selectedAction = $actionEntries[$selectedActionIndex]
                    if ($selectedAction.IsEnabled) {
                        if ($isQueryMode) {
                            if ($selectedAction.Shortcut -eq 'x') {
                                . $executeSelectedQuery
                            }
                            elseif ($selectedAction.Shortcut -eq 'h') {
                                $isQueryMode = $false
                                $activePanel = 'incidents'
                                $activePanelIndex = [array]::IndexOf($panelOrder, 'incidents')
                                $context.Selection.Panel = $activePanel
                                Set-LiveStatusMessage -Context $context -Message 'Returned to incident workflow.' -Level 'info'
                            }
                        }
                        else {
                            Invoke-XdrLiveActionShortcut -Shortcut $selectedAction.Shortcut -Context $context -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -TriageOptions $triageOptions -PanelOrder $panelOrder -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -ActivePanelBeforeResolution ([ref]$activePanelBeforeResolution) -PendingConfirmation ([ref]$pendingConfirmation) -PendingTextInput ([ref]$pendingTextInput) -PendingIncidentResolution ([ref]$pendingIncidentResolution) -ActivePanelBeforeClassification ([ref]$activePanelBeforeClassification) -PendingIncidentClassification ([ref]$pendingIncidentClassification) -ActivePanelBeforeComment ([ref]$activePanelBeforeComment) -PendingIncidentComment ([ref]$pendingIncidentComment) -ModulePath $modulePath -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlertIndex ([ref]$selectedAlertIndex) -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId)
                        }
                    }
                    else {
                        Set-LiveStatusMessage -Context $context -Message "$($selectedAction.Label) is not available right now." -Level 'warning'
                    }
                }
                elseif ($isAltPressed -and $isShiftPressed -and $key.Key -eq 'L') {
                    Invoke-XdrLiveActionShortcut -Shortcut 'reload-alerts' -Context $context -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -TriageOptions $triageOptions -PanelOrder $panelOrder -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -ActivePanelBeforeResolution ([ref]$activePanelBeforeResolution) -PendingConfirmation ([ref]$pendingConfirmation) -PendingTextInput ([ref]$pendingTextInput) -PendingIncidentResolution ([ref]$pendingIncidentResolution) -ActivePanelBeforeClassification ([ref]$activePanelBeforeClassification) -PendingIncidentClassification ([ref]$pendingIncidentClassification) -ActivePanelBeforeComment ([ref]$activePanelBeforeComment) -PendingIncidentComment ([ref]$pendingIncidentComment) -ModulePath $modulePath -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlertIndex ([ref]$selectedAlertIndex) -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId)
                }
                elseif ($isAltPressed -and $keyChar -in @('a', 'u', 'o', 'i', 'r', 'k', 'c', 'l', 'n', 'p', 'm')) {
                    Invoke-XdrLiveActionShortcut -Shortcut $keyChar -Context $context -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -TriageOptions $triageOptions -PanelOrder $panelOrder -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -ActivePanelBeforeResolution ([ref]$activePanelBeforeResolution) -PendingConfirmation ([ref]$pendingConfirmation) -PendingTextInput ([ref]$pendingTextInput) -PendingIncidentResolution ([ref]$pendingIncidentResolution) -ActivePanelBeforeClassification ([ref]$activePanelBeforeClassification) -PendingIncidentClassification ([ref]$pendingIncidentClassification) -ActivePanelBeforeComment ([ref]$activePanelBeforeComment) -PendingIncidentComment ([ref]$pendingIncidentComment) -ModulePath $modulePath -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlertIndex ([ref]$selectedAlertIndex) -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId)
                }

                $context.Diagnostics.LastInput = [pscustomobject][ordered]@{
                    Timestamp          = $currentInputTime
                    Key                = [string]$key.Key
                    KeyChar            = $keyCharDisplay
                    Modifiers          = $modifierSummary
                    ActivePanel        = [string]$activePanel
                    IsQueryMode        = [bool]$isQueryMode
                    SelectedQueryIndex = [int]$selectedQueryIndex
                    SelectedQueryId    = $(if ($selectedQuery) { [string]$selectedQuery.id } else { '' })
                    SelectedEntity     = $(if ($selectedEntity) { [string]$selectedEntity.DisplayName } else { '' })
                    KeyHandled         = [bool]$keyHandled
                }
            }  # end foreach ($key in $keys)

            if (-not $context.Data.Incidents) {
                $selectedEntity = $null
                $context.Selection.Entity = $null
                $layout['header'].Update((Get-XdrLiveHeaderPanel -Context $context -ScriptRoot $PSScriptRoot)) | Out-Null
                $layout['incidents'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No incidents found. Press Ctrl+C to exit.' -Expand)) | Out-Null
                $emptyIncidentDetailsData = if ($selectedIncidentDetailsTab -eq 'entities') { 'No incident selected. Press Alt+E for entities view.' } else { 'No incident selected.' }
                $layout['incident_details'].Update((Format-SpectrePanel -Header $incidentDetailsHeader -Data $emptyIncidentDetailsData -Expand)) | Out-Null
                $layout['alerts'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alerts' -Title 'Alert List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No incident selected.' -Expand)) | Out-Null
                $layout['alert_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No alert selected.' -Expand)) | Out-Null
                $layout['action_status'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No incident selected.' -Expand)) | Out-Null
                $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -SelectedIncident $selectedIncident -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -LastRefreshAt $lastDataRefreshAt -HeartbeatAt $lastHeartbeat -HeartbeatCounter $heartbeatCounter) -Expand)) | Out-Null
                $LiveContext.Refresh()
                Start-Sleep -Milliseconds $context.Ui.RefreshIntervalMs
                continue
            }

            $incidentLines = @('Sev ID         Title                                    Status')
            $incidentLines += @($context.Data.Incidents | ForEach-Object {
                $incidentIdText = [string]$_.IncidentId
                $displayNameText = [string]$_.DisplayName
                $statusText = [string]$_.Status
                $severityText = [string]$_.Severity
                $severityKey = if ([string]::IsNullOrWhiteSpace($severityText)) { '' } else { $severityText.ToLowerInvariant() }
                $statusKey = if ([string]::IsNullOrWhiteSpace($statusText)) { '' } else { $statusText.ToLowerInvariant() }

                $severityGlyph = switch ($severityKey) {
                    'high' { 'Ⓗ' }
                    'medium' { 'Ⓜ' }
                    'low' { 'Ⓛ' }
                    default { 'Ⓤ' }
                }

                $severityColor = switch ($severityKey) {
                    'high' { 'red' }
                    'medium' { 'yellow' }
                    'low' { 'green' }
                    default { 'grey' }
                }
                $severityColumn = $severityGlyph.PadRight(3)

                $statusColor = switch -Regex ($statusKey) {
                    '^active$|^new$' { 'deepskyblue1' }
                    '^in ?progress$' { 'yellow' }
                    '^resolved$' { 'lightgreen' }
                    default { 'grey' }
                }

                $idColumn = ("#{0}" -f $incidentIdText)
                if ($idColumn.Length -gt 10) { $idColumn = $idColumn.Substring(0, 10) }
                $idColumn = $idColumn.PadRight(10)

                $titleColumn = $displayNameText
                if ($titleColumn.Length -gt 40) { $titleColumn = $titleColumn.Substring(0, 37) + '...' }
                $titleColumn = $titleColumn.PadRight(40)

                $statusColumn = if ([string]::IsNullOrWhiteSpace($statusText)) { 'Unknown' } else { $statusText }
                if ($statusColumn.Length -gt 6) { $statusColumn = $statusColumn.Substring(0, 6) }

                $rowPrefix = "[bold $severityColor]$severityColumn[/] $idColumn $titleColumn "
                $rowStatus = "[bold $statusColor]$statusColumn[/]"

                if ($_.IncidentId -eq $selectedIncident.IncidentId) {
                    "[bold $severityColor]$severityColumn[/] [bold $($context.Ui.ThemeColor)]$idColumn $titleColumn[/] $rowStatus"
                }
                else {
                    "$rowPrefix$rowStatus"
                }
            })

            $incidentPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title "Incident List ($($context.Data.Incidents.Count))" -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data (($incidentLines | Out-String)) -Color (Get-PanelBorderColor -PanelName 'incidents' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'incidents' -ActivePanel $activePanel) -Expand

            $incidentDetails = if ($selectedIncidentDetailsTab -eq 'entities') {
                $entityLines = @()
                $entityLines += '[bold grey]Incident-linked entities[/]'

                $runtimeEntities = @($context.Data.Entities | Where-Object {
                        $entityIncidentId = [string]$_.IncidentId
                        -not [string]::IsNullOrWhiteSpace($entityIncidentId) -and $entityIncidentId -eq [string]$selectedIncident.IncidentId
                    })
                $entityEntries = @($runtimeEntities)

                if ($entityEntries.Count -eq 0) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$selectedIncident.AssignedTo)) {
                        $entityEntries += [pscustomobject]@{
                            EntityType = 'User'
                            DisplayName = [string]$selectedIncident.AssignedTo
                            IncidentId = [string]$selectedIncident.IncidentId
                            AlertId = $null
                        }
                    }

                    $relatedAlertRows = @($visibleAlerts | Where-Object {
                            [string]$_.IncidentId -eq [string]$selectedIncident.IncidentId
                        })

                    foreach ($alertRow in $relatedAlertRows) {
                        $alertEntityLabel = if ([string]::IsNullOrWhiteSpace([string]$alertRow.Title)) {
                            [string]$alertRow.AlertId
                        }
                        else {
                            [string]$alertRow.Title
                        }

                        $entityEntries += [pscustomobject]@{
                            EntityType = 'Alert'
                            DisplayName = $alertEntityLabel
                            IncidentId = [string]$selectedIncident.IncidentId
                            AlertId = [string]$alertRow.AlertId
                        }
                    }
                }

                if ($entityEntries.Count -gt 0) {
                    $selectedEntityIndex = [Math]::Min([Math]::Max($selectedEntityIndex, 0), $entityEntries.Count - 1)
                    $selectedEntity = $entityEntries[$selectedEntityIndex]
                    $context.Selection.Entity = $selectedEntity
                    $distinctEntityAlertIds = @($entityEntries | Where-Object {
                            -not [string]::IsNullOrWhiteSpace([string]$_.AlertId)
                        } | ForEach-Object {
                            [string]$_.AlertId
                        } | Select-Object -Unique)
                    $shouldSeparateEntityAlertGroups = $distinctEntityAlertIds.Count -gt 1
                    $previousEntityAlertId = $null

                    for ($entityIdx = 0; $entityIdx -lt $entityEntries.Count; $entityIdx++) {
                        $entity = $entityEntries[$entityIdx]
                        $entityAlertId = if ($entity.PSObject.Properties.Name -contains 'AlertId') {
                            [string]$entity.AlertId
                        }
                        else {
                            $null
                        }

                        if (
                            $shouldSeparateEntityAlertGroups -and
                            -not [string]::IsNullOrWhiteSpace($entityAlertId) -and
                            -not [string]::IsNullOrWhiteSpace($previousEntityAlertId) -and
                            $entityAlertId -ne $previousEntityAlertId
                        ) {
                            $entityLines += ''
                        }

                        $entityType = if ($entity.PSObject.Properties.Name -contains 'EntityType' -and -not [string]::IsNullOrWhiteSpace([string]$entity.EntityType)) {
                            [string]$entity.EntityType
                        }
                        elseif ($entity.PSObject.Properties.Name -contains 'UserId') {
                            'User'
                        }
                        elseif ($entity.PSObject.Properties.Name -contains 'DeviceId') {
                            'Device'
                        }
                        elseif ($entity.PSObject.Properties.Name -contains 'Sha256') {
                            'File'
                        }
                        else {
                            'Entity'
                        }

                        $entityValue = if ($entity.PSObject.Properties.Name -contains 'DisplayName' -and -not [string]::IsNullOrWhiteSpace([string]$entity.DisplayName)) {
                            [string]$entity.DisplayName
                        }
                        elseif ($entity.PSObject.Properties.Name -contains 'UserPrincipalName' -and -not [string]::IsNullOrWhiteSpace([string]$entity.UserPrincipalName)) {
                            [string]$entity.UserPrincipalName
                        }
                        elseif ($entity.PSObject.Properties.Name -contains 'DeviceId' -and -not [string]::IsNullOrWhiteSpace([string]$entity.DeviceId)) {
                            [string]$entity.DeviceId
                        }
                        elseif ($entity.PSObject.Properties.Name -contains 'UserId' -and -not [string]::IsNullOrWhiteSpace([string]$entity.UserId)) {
                            [string]$entity.UserId
                        }
                        elseif ($entity.PSObject.Properties.Name -contains 'Sha256' -and -not [string]::IsNullOrWhiteSpace([string]$entity.Sha256)) {
                            [string]$entity.Sha256
                        }
                        else {
                            'Unknown'
                        }

                        $isSelectedEntity = ($entityIdx -eq $selectedEntityIndex)
                        $entityPrefix = if ($isSelectedEntity -and $activePanel -eq 'incident_details') { "[bold $($context.Ui.ThemeColor)]>[/]" } else { ' ' }
                        $entityTypeMarkup = if ($isSelectedEntity) { "[bold $($context.Ui.ThemeColor)]$([string](Get-SpectreEscapedText $entityType))[/]" } else { "[white]$([string](Get-SpectreEscapedText $entityType))[/]" }
                        $entityValueMarkup = if ($isSelectedEntity) { "[bold $($context.Ui.ThemeColor)]$([string](Get-SpectreEscapedText $entityValue))[/]" } else { "[grey]$([string](Get-SpectreEscapedText $entityValue))[/]" }
                        $entityLines += "$entityPrefix ${entityTypeMarkup}: $entityValueMarkup"

                        if (-not [string]::IsNullOrWhiteSpace($entityAlertId)) {
                            $previousEntityAlertId = $entityAlertId
                        }
                    }
                }
                else {
                    $selectedEntity = $null
                    $context.Selection.Entity = $null
                }

                if ($entityLines.Count -le 1) {
                    $entityLines += '[grey]No related entities are available yet for this incident.[/]'
                }

                $entityLines += ''
                $entityLines += '[grey]Tab to switch to Details • Use ↑↓ to navigate[/]'

                Format-SpectrePanel -Header $incidentDetailsHeader -Data ($entityLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'incident_details' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'incident_details' -ActivePanel $activePanel) -Expand
            }
            else {
                [pscustomobject]@{
                    IncidentId    = $selectedIncident.IncidentId
                    DisplayName   = $selectedIncident.DisplayName
                    Status        = $selectedIncident.Status
                    Classification = $selectedIncident.Classification
                    Determination = $selectedIncident.Determination
                    AssignedTo    = $selectedIncident.AssignedTo
                    Severity      = $selectedIncident.Severity
                    AlertCount    = $selectedIncident.AlertCount
                    SystemTags    = @($selectedIncident.SystemTags)
                    CustomTags    = @($selectedIncident.CustomTags)
                    LastUpdated   = $selectedIncident.LastUpdateDateTime
                    IncidentWebUrl = $selectedIncident.IncidentWebUrl
                    Created       = $selectedIncident.CreatedDateTime
                } | Format-SpectreJson | Format-SpectrePanel -Header $incidentDetailsHeader -Color (Get-PanelBorderColor -PanelName 'incident_details' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'incident_details' -ActivePanel $activePanel) -Expand
            }

            $alertLines = if ($visibleAlerts) {
                @('Sev Title                                         Status')
                @($visibleAlerts | ForEach-Object {
                    $titleText = [string]$_.Title
                    $statusText = [string]$_.Status
                    $severityText = [string]$_.Severity
                    $severityKey = if ([string]::IsNullOrWhiteSpace($severityText)) { '' } else { $severityText.ToLowerInvariant() }
                    $statusKey = if ([string]::IsNullOrWhiteSpace($statusText)) { '' } else { $statusText.ToLowerInvariant() }

                    $severityGlyph = switch ($severityKey) {
                        'high' { 'Ⓗ' }
                        'medium' { 'Ⓜ' }
                        'low' { 'Ⓛ' }
                        default { 'Ⓤ' }
                    }

                    $severityColor = switch ($severityKey) {
                        'high' { 'red' }
                        'medium' { 'yellow' }
                        'low' { 'green' }
                        default { 'grey' }
                    }
                    $severityColumn = $severityGlyph.PadRight(3)

                    $statusColor = switch -Regex ($statusKey) {
                        '^active$|^new$' { 'deepskyblue1' }
                        '^in ?progress$' { 'yellow' }
                        '^resolved$' { 'lightgreen' }
                        default { 'grey' }
                    }

                    $titleColumn = $titleText
                    if ($titleColumn.Length -gt 46) { $titleColumn = $titleColumn.Substring(0, 43) + '...' }
                    $titleColumn = $titleColumn.PadRight(46)

                    $statusColumn = if ([string]::IsNullOrWhiteSpace($statusText)) { 'Unknown' } else { $statusText }
                    if ($statusColumn.Length -gt 6) { $statusColumn = $statusColumn.Substring(0, 6) }

                    if ($selectedAlert -and $_.AlertId -eq $selectedAlert.AlertId) {
                        "[bold $severityColor]$severityColumn[/] [bold $($context.Ui.ThemeColor)]$titleColumn[/] [bold $statusColor]$statusColumn[/]"
                    }
                    else {
                        "[bold $severityColor]$severityColumn[/] $titleColumn [bold $statusColor]$statusColumn[/]"
                    }
                })
            }
            else {
                @('Press Enter on an incident to load alerts.')
            }

            $alertsPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alerts' -Title "Alert List ($($visibleAlerts.Count))" -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data (($alertLines | Out-String)) -Color (Get-PanelBorderColor -PanelName 'alerts' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'alerts' -ActivePanel $activePanel) -Expand

            $alertDetails = if ($selectedAlert) {
                [pscustomobject]@{
                    AlertId     = $selectedAlert.AlertId
                    Title       = $selectedAlert.Title
                    Status      = $selectedAlert.Status
                    Severity    = $selectedAlert.Severity
                    Created     = $selectedAlert.CreatedDateTime
                    AlertWebUrl = $selectedAlert.AlertWebUrl
                } | Format-SpectreJson | Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Color (Get-PanelBorderColor -PanelName 'alert_details' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'alert_details' -ActivePanel $activePanel) -Expand
            }
            else {
                Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No alert selected.' -Color (Get-PanelBorderColor -PanelName 'alert_details' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'alert_details' -ActivePanel $activePanel) -Expand
            }

            $incidentActionLines = @()
            $actionEntries = @()
            $actionLines = @()

            if ($selectedIncidentDetailsTab -eq 'entities') {
                $actionLines += 'Entity actions (preview)'

                if ($selectedEntity) {
                    $selectedEntityType = [string]$selectedEntity.EntityType
                    $entityPreviewActions = switch -Regex ($selectedEntityType) {
                        '^(?i:user|account)$' { @('Revoke user sessions', 'Disable user account') }
                        '^(?i:device|machine)$' { @('Isolate device', 'Run antivirus scan', 'Collect investigation package') }
                        '^(?i:file)$' { @('Quarantine file', 'Block file indicator', 'Remove file indicator block') }
                        '^(?i:alert)$' { @('Open alert details', 'Load alert timeline') }
                        default { @('Entity actions coming soon') }
                    }

                    foreach ($entityAction in $entityPreviewActions) {
                        $entityReasons = @('Not implemented yet')
                        $actionLines += (New-ActionStateLine -Label "(Alt+X) $entityAction" -Reasons $entityReasons)
                        $actionEntries += [pscustomobject]@{ Shortcut = ''; Label = $entityAction; IsEnabled = $false; Reasons = $entityReasons }
                    }
                }
                else {
                    $actionLines += '[grey]No entity selected.[/]'
                }

                $actionLines += ''
            }

            $incidentActionLines += 'Incident actions'
            $reasons = @(Get-XdrActionDisableReasons -ActionName 'Assign incident to me' -ActionType Incident -Context $context)
            $incidentActionLines += (New-ActionStateLine -Label '(Alt+A) Assign incident to me' -Reasons $reasons)
            $actionEntries += [pscustomobject]@{ Shortcut = 'a'; Label = 'Assign incident to me'; IsEnabled = ($reasons.Count -eq 0); Reasons = $reasons }
            $reasons = @(Get-XdrActionDisableReasons -ActionName 'Clear incident assignment' -ActionType Incident -Context $context)
            $incidentActionLines += (New-ActionStateLine -Label '(Alt+U) Clear incident assignment' -Reasons $reasons)
            $actionEntries += [pscustomobject]@{ Shortcut = 'u'; Label = 'Clear incident assignment'; IsEnabled = ($reasons.Count -eq 0); Reasons = $reasons }

            foreach ($statusLabel in @('Active', 'In progress', 'Resolved')) {
                $requestedStatus = Resolve-XdrGraphEnumValue -MapName 'incidentStatusMap' -DisplayValue $statusLabel
                $shortcut = switch ($statusLabel) {
                    'Active' { '(Alt+O)' }
                    'In progress' { '(Alt+I)' }
                    'Resolved' { '(Alt+R)' }
                }
                $shortcutKey = switch ($statusLabel) {
                    'Active' { 'o' }
                    'In progress' { 'i' }
                    'Resolved' { 'r' }
                }
                $reasons = @(Get-XdrActionDisableReasons -ActionName "Set incident status to $statusLabel" -ActionType Incident -Context $context -CurrentStatus $selectedIncident.Status -RequestedStatus $requestedStatus)
                $incidentActionLines += (New-ActionStateLine -Label "$shortcut Set incident status to $statusLabel" -Reasons $reasons)
                $actionEntries += [pscustomobject]@{ Shortcut = $shortcutKey; Label = "Set incident status to $statusLabel"; IsEnabled = ($reasons.Count -eq 0); Reasons = $reasons }
            }
            $classificationReasons = @(Get-XdrActionDisableReasons -ActionName 'Set incident classification' -ActionType Incident -Context $context)
            $incidentActionLines += (New-ActionStateLine -Label '(Alt+K) Set incident classification' -Reasons $classificationReasons)
            $actionEntries += [pscustomobject]@{ Shortcut = 'k'; Label = 'Set incident classification'; IsEnabled = ($classificationReasons.Count -eq 0); Reasons = $classificationReasons }
            $incidentCommentReasons = @(Get-XdrActionDisableReasons -ActionName 'Add comment to selected incident' -ActionType Incident -Context $context)
            $incidentActionLines += (New-ActionStateLine -Label '(Alt+C) Add comment to selected incident' -Reasons $incidentCommentReasons)
            $actionEntries += [pscustomobject]@{ Shortcut = 'c'; Label = 'Add comment to selected incident'; IsEnabled = ($incidentCommentReasons.Count -eq 0); Reasons = $incidentCommentReasons }
            $incidentActionLines += '(Alt+L) Load alerts for selected incident'
            $actionEntries += [pscustomobject]@{ Shortcut = 'l'; Label = 'Load alerts for selected incident'; IsEnabled = $true; Reasons = @() }
            $incidentActionLines += '(Alt+Shift+L) Force reload alerts for selected incident'
            $actionEntries += [pscustomobject]@{ Shortcut = 'reload-alerts'; Label = 'Force reload alerts for selected incident'; IsEnabled = $true; Reasons = @() }

            $actionLines += @($incidentActionLines)
            $actionLines += ''
            $actionLines += 'Alert actions'

            if ($selectedAlert) {
                foreach ($statusLabel in @('New', 'In progress', 'Resolved')) {
                    $requestedStatus = Resolve-XdrGraphEnumValue -MapName 'alertStatusMap' -DisplayValue $statusLabel
                    $shortcut = switch ($statusLabel) {
                        'New' { '(Alt+N)' }
                        'In progress' { '(Alt+P)' }
                        'Resolved' { '(Alt+M)' }
                    }
                    $shortcutKey = switch ($statusLabel) {
                        'New' { 'n' }
                        'In progress' { 'p' }
                        'Resolved' { 'm' }
                    }
                    $reasons = @(Get-XdrActionDisableReasons -ActionName "Set alert status to $statusLabel" -ActionType Alert -Context $context -CurrentStatus $selectedAlert.Status -RequestedStatus $requestedStatus)
                    $actionLines += (New-ActionStateLine -Label "$shortcut Set alert status to $statusLabel" -Reasons $reasons)
                    $actionEntries += [pscustomobject]@{ Shortcut = $shortcutKey; Label = "Set alert status to $statusLabel"; IsEnabled = ($reasons.Count -eq 0); Reasons = $reasons }
                }
            }
            else {
                foreach ($statusLabel in @('New', 'In progress', 'Resolved')) {
                    $shortcut = switch ($statusLabel) {
                        'New' { '(Alt+N)' }
                        'In progress' { '(Alt+P)' }
                        'Resolved' { '(Alt+M)' }
                    }
                    $shortcutKey = switch ($statusLabel) {
                        'New' { 'n' }
                        'In progress' { 'p' }
                        'Resolved' { 'm' }
                    }
                    $reasons = @('Unavailable')
                    $actionLines += (New-ActionStateLine -Label "$shortcut Set alert status to $statusLabel" -Reasons $reasons)
                    $actionEntries += [pscustomobject]@{
                        Shortcut = $shortcutKey
                        Label    = "Set alert status to $statusLabel"
                        IsEnabled = $false
                        Reasons  = $reasons
                    }
                }
            }

            if ($actionEntries.Count -eq 0) {
                $selectedActionIndex = 0
            }
            else {
                $selectedActionIndex = [Math]::Min($selectedActionIndex, $actionEntries.Count - 1)
            }

            $actionCursor = 0
            $actionDisplayLines = @($actionLines | ForEach-Object {
                $line = [string]$_

                if ([string]::IsNullOrWhiteSpace($line)) {
                    return ''
                }

                if ($line -in @('Incident actions', 'Alert actions')) {
                    return "[bold grey]$(Get-SpectreEscapedText $line)[/]"
                }

                if ($line -match '^\(((?:Alt\+[A-Z])|ⓧ)\)\s+(.+)$') {
                    $shortcutSymbol = [string]$Matches[1]
                    $labelText = [string]$Matches[2]
                    $isEnabled = $shortcutSymbol -ne 'ⓧ'
                    $isSelected = ($activePanel -eq 'action_status' -and $actionCursor -eq $selectedActionIndex)
                    $actionCursor++

                    $prefix = if ($isSelected) { "[bold $($context.Ui.ThemeColor)]>[/] " } else { '  ' }
                    $shortcutMarkup = if ($isEnabled) {
                        if ($isSelected) { "[bold $($context.Ui.ThemeColor)]($shortcutSymbol)[/]" } else { "[bold deepskyblue1]($shortcutSymbol)[/]" }
                    }
                    else {
                        '[grey]([/][darkred]ⓧ[/][grey])[/]'
                    }

                    $escapedLabel = Get-SpectreEscapedText $labelText
                    if ($isEnabled) {
                        $labelMarkup = if ($isSelected) { "[bold $($context.Ui.ThemeColor)]$escapedLabel[/]" } else { "[white]$escapedLabel[/]" }
                    }
                    else {
                        $labelMarkup = if ($isSelected) { "[bold grey]$escapedLabel[/]" } else { "[grey]$escapedLabel[/]" }
                    }

                    return "$prefix$shortcutMarkup $labelMarkup"
                }

                return "  [grey]$(Get-SpectreEscapedText $line)[/]"
            })

            if ($null -ne $pendingIncidentResolution) {
                $resolutionLines = @()
                $selectedClassificationOption = $pendingIncidentResolution.ClassificationOptions[[int]$pendingIncidentResolution.ClassificationIndex]
                $selectedClassificationLabel = Get-SpectreEscapedText ([string]$selectedClassificationOption.label)
                $selectedDeterminationOption = $pendingIncidentResolution.DeterminationOptions[[int]$pendingIncidentResolution.DeterminationIndex]
                $selectedDeterminationLabel = Get-SpectreEscapedText ([string]$selectedDeterminationOption.label)
                $commentValue = [string]$pendingIncidentResolution.ResolvingComment
                $stepName = [string]$pendingIncidentResolution.Step

                switch ($stepName) {
                    'classification' {
                        $resolutionLines += "[bold $($context.Ui.ThemeColor)]Step 1/4: Classification[/]"
                        $resolutionLines += ''
                        foreach ($idx in 0..([Math]::Max(0, @($pendingIncidentResolution.ClassificationOptions).Count - 1))) {
                            if (@($pendingIncidentResolution.ClassificationOptions).Count -eq 0) {
                                break
                            }

                            $option = $pendingIncidentResolution.ClassificationOptions[$idx]
                            $label = Get-SpectreEscapedText ([string]$option.label)
                            $prefix = if ($pendingIncidentResolution.ClassificationIndex -eq $idx) { "[bold $($context.Ui.ThemeColor)]>[/]" } else { ' ' }
                            $color = if ($pendingIncidentResolution.ClassificationIndex -eq $idx) { $context.Ui.ThemeColor } else { 'white' }
                            $resolutionLines += "$prefix [bold $color]$label[/]"
                        }
                        $resolutionLines += ''
                        $resolutionLines += '[grey][orange1]Enter[/] or [orange1]PgDn[/] next | [orange1]Up[/]/[orange1]Down[/] select | [orange1]Esc[/] cancel[/]'
                    }
                    'determination' {
                        $resolutionLines += "[bold $($context.Ui.ThemeColor)]Step 2/4: Determination[/]"
                        $resolutionLines += ''
                        foreach ($idx in 0..([Math]::Max(0, @($pendingIncidentResolution.DeterminationOptions).Count - 1))) {
                            if (@($pendingIncidentResolution.DeterminationOptions).Count -eq 0) {
                                break
                            }

                            $option = $pendingIncidentResolution.DeterminationOptions[$idx]
                            $label = Get-SpectreEscapedText ([string]$option.label)
                            $prefix = if ($pendingIncidentResolution.DeterminationIndex -eq $idx) { "[bold $($context.Ui.ThemeColor)]>[/]" } else { ' ' }
                            $color = if ($pendingIncidentResolution.DeterminationIndex -eq $idx) { $context.Ui.ThemeColor } else { 'white' }
                            $resolutionLines += "$prefix [bold $color]$label[/]"
                        }
                        $resolutionLines += ''
                        $resolutionLines += '[grey][orange1]Enter[/] or [orange1]PgDn[/] next | [orange1]PgUp[/] back | [orange1]Up[/]/[orange1]Down[/] select | [orange1]Esc[/] cancel[/]'
                    }
                    'comment' {
                        $resolutionLines += "[bold $($context.Ui.ThemeColor)]Step 3/4: Resolving comment[/]"
                        $resolutionLines += ''
                        if ([string]::IsNullOrWhiteSpace($commentValue)) {
                            $resolutionLines += '[grey]<empty - default comment will be used>[/]'
                        }
                        else {
                            $resolutionLines += "[white]$(Get-SpectreEscapedText $commentValue)[/]"
                        }
                        $resolutionLines += ''
                        $resolutionLines += '[grey]Type comment | [orange1]Enter[/] or [orange1]PgDn[/] next | [orange1]PgUp[/] back | [orange1]Esc[/] cancel[/]'
                    }
                    default {
                        $resolutionLines += "[bold $($context.Ui.ThemeColor)]Step 4/4: Final confirmation[/]"
                        $resolutionLines += ''
                        $resolutionLines += "[white]Classification:[/] [bold]$selectedClassificationLabel[/]"
                        $resolutionLines += "[white]Determination:[/] [bold]$selectedDeterminationLabel[/]"
                        $resolutionLines += "[white]Ready to resolve this incident.[/]"
                        $resolutionLines += ''
                        $resolutionLines += '[grey][orange1]Enter[/] or [orange1]Y[/] confirm | [orange1]N[/] or [orange1]PgUp[/] back | [orange1]Esc[/] cancel[/]'
                    }
                }

                $actionStatusPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Incident Resolution Wizard' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($resolutionLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'action_status' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'action_status' -ActivePanel $activePanel) -Expand
            }
            elseif ($null -ne $pendingIncidentClassification) {
                $classificationLines = @()
                $classificationStep = [string]$pendingIncidentClassification.Step
                if ([string]::IsNullOrWhiteSpace($classificationStep)) {
                    $classificationStep = 'classification'
                }

                if ($classificationStep -eq 'confirm') {
                    $selectedClassificationOption = $pendingIncidentClassification.ClassificationOptions[[int]$pendingIncidentClassification.ClassificationIndex]
                    $selectedClassificationLabel = Get-SpectreEscapedText ([string]$selectedClassificationOption.label)
                    $classificationLines += "[bold $($context.Ui.ThemeColor)]Step 2/2: Final confirmation[/]"
                    $classificationLines += ''
                    $classificationLines += "[white]Classification:[/] [bold]$selectedClassificationLabel[/]"
                    $classificationLines += "[white]Ready to apply this incident classification.[/]"
                    $classificationLines += ''
                    $classificationLines += '[grey][orange1]Enter[/] or [orange1]Y[/] confirm | [orange1]N[/] or [orange1]PgUp[/] back | [orange1]Esc[/] cancel[/]'
                }
                else {
                    $classificationLines += "[bold $($context.Ui.ThemeColor)]Step 1/2: Classification[/]"
                    $classificationLines += ''
                    foreach ($idx in 0..([Math]::Max(0, @($pendingIncidentClassification.ClassificationOptions).Count - 1))) {
                        if (@($pendingIncidentClassification.ClassificationOptions).Count -eq 0) {
                            break
                        }

                        $option = $pendingIncidentClassification.ClassificationOptions[$idx]
                        $label = Get-SpectreEscapedText ([string]$option.label)
                        $prefix = if ($pendingIncidentClassification.ClassificationIndex -eq $idx) { "[bold $($context.Ui.ThemeColor)]>[/]" } else { ' ' }
                        $color = if ($pendingIncidentClassification.ClassificationIndex -eq $idx) { $context.Ui.ThemeColor } else { 'white' }
                        $classificationLines += "$prefix [bold $color]$label[/]"
                    }

                    $classificationLines += ''
                    $classificationLines += '[grey][orange1]Enter[/] or [orange1]PgDn[/] next | [orange1]Up[/]/[orange1]Down[/] select | [orange1]Esc[/] cancel[/]'
                }

                $actionStatusPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Incident Classification Wizard' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($classificationLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'action_status' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'action_status' -ActivePanel $activePanel) -Expand
            }
            elseif ($null -ne $pendingIncidentComment) {
                $commentLines = @()
                $commentStep = [string]$pendingIncidentComment.Step
                if ([string]::IsNullOrWhiteSpace($commentStep)) {
                    $commentStep = 'comment'
                }

                if ($commentStep -eq 'confirm') {
                    $commentValue = Get-SpectreEscapedText ([string]$pendingIncidentComment.Comment)
                    $commentLines += "[bold $($context.Ui.ThemeColor)]Step 2/2: Final confirmation[/]"
                    $commentLines += ''
                    $commentLines += '[white]Comment:[/]'
                    $commentLines += "[white]$commentValue[/]"
                    $commentLines += ''
                    $commentLines += '[grey][orange1]Enter[/] or [orange1]Y[/] confirm | [orange1]N[/] or [orange1]PgUp[/] back | [orange1]Esc[/] cancel[/]'
                }
                else {
                    $commentLines += "[bold $($context.Ui.ThemeColor)]Step 1/2: Incident comment[/]"
                    $commentLines += ''
                    $commentValue = [string]$pendingIncidentComment.Comment
                    if ([string]::IsNullOrWhiteSpace($commentValue)) {
                        $commentLines += '[grey]<empty>[/]'
                    }
                    else {
                        $commentLines += "[white]$(Get-SpectreEscapedText $commentValue)[/]"
                    }
                    $commentLines += ''
                    $commentLines += '[grey]Type comment | [orange1]Enter[/] or [orange1]PgDn[/] next | [orange1]Backspace[/] edit | [orange1]Esc[/] cancel[/]'
                }

                $actionStatusPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Incident Comment Wizard' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($commentLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'action_status' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'action_status' -ActivePanel $activePanel) -Expand
            }
            else {
                $actionStatusPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($actionDisplayLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'action_status' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'action_status' -ActivePanel $activePanel) -Expand
            }

            if ($isQueryMode) {
                . $syncSelectedQuery

                $queryCatalogLines = @()
                $queryRunHistory = @($context.Data.QueryRuns | Sort-Object -Property ExecutedAt -Descending)
                $selectedQueryResolution = $null
                $selectedQueryPreview = $null
                $selectedQueryPreviewError = $null

                if ($selectedQuery) {
                    $selectedQueryResolution = Resolve-XdrQueryParameters -Query $selectedQuery -Context $context
                    if (-not $selectedQueryResolution.IsBlocked) {
                        try {
                            $selectedQueryPreview = (Invoke-XdrQueryInterpolation -Query $selectedQuery -Parameters $selectedQueryResolution.Parameters).Kql
                        }
                        catch {
                            $selectedQueryPreviewError = [string]$_.Exception.Message
                        }
                    }
                }

                if (@($context.Data.QueryCatalog).Count -eq 0) {
                    $queryCatalogLines += '[grey]No hunting queries were loaded from the repository catalog.[/]'
                }
                else {
                    foreach ($queryCursor in 0..([Math]::Max(0, @($context.Data.QueryCatalog).Count - 1))) {
                        if (@($context.Data.QueryCatalog).Count -eq 0) {
                            break
                        }

                        $queryDefinition = $context.Data.QueryCatalog[$queryCursor]
                        $queryResolution = Resolve-XdrQueryParameters -Query $queryDefinition -Context $context
                        $isSelectedQuery = $selectedQuery -and ([string]$queryDefinition.id -eq [string]$selectedQuery.id)
                        $queryPrefix = if ($isSelectedQuery -and $activePanel -eq 'incidents') { "[bold $($context.Ui.ThemeColor)]>[/]" } else { ' ' }
                        $queryNameMarkup = if ($isSelectedQuery) { "[bold $($context.Ui.ThemeColor)]$([string](Get-SpectreEscapedText ([string]$queryDefinition.name)))[/]" } else { "[white]$([string](Get-SpectreEscapedText ([string]$queryDefinition.name)))[/]" }
                        $queryStatusMarkup = if ($queryResolution.IsBlocked) { '[bold red]BLOCKED[/]' } else { '[bold green]READY[/]' }
                        $queryCatalogLines += "$queryPrefix $queryNameMarkup $queryStatusMarkup"
                        $queryCatalogLines += "  [grey]$([string](Get-SpectreEscapedText ([string]$queryDefinition.description)))[/]"

                        if ($queryResolution.IsBlocked) {
                            $queryCatalogLines += "  [darkred]Missing: $([string](Get-SpectreEscapedText (($queryResolution.MissingContext -join ', '))))[/]"
                            $queryCatalogLines += "  [grey]Hint: $([string](Get-SpectreEscapedText ([string](& $getQueryContextGuidance $queryResolution.MissingContext[0]))))[/]"
                        }
                        elseif (@($queryDefinition.tags).Count -gt 0) {
                            $queryCatalogLines += "  [grey]Tags: $([string](Get-SpectreEscapedText ((@($queryDefinition.tags) -join ', '))))[/]"
                        }

                        $queryCatalogLines += ''
                    }
                }

                $incidentPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title "Query Catalog ($(@($context.Data.QueryCatalog).Count))" -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($queryCatalogLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'incidents' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'incidents' -ActivePanel $activePanel) -Expand

                if (-not $selectedQuery) {
                    $incidentDetails = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title 'Query Preview' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No hunting query selected.' -Color (Get-PanelBorderColor -PanelName 'incident_details' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'incident_details' -ActivePanel $activePanel) -Expand
                }
                elseif ($selectedQueryResolution.IsBlocked) {
                    $blockedPreviewLines = @(
                        "[bold]$([string](Get-SpectreEscapedText ([string]$selectedQuery.name)))[/]",
                        "[grey]$([string](Get-SpectreEscapedText ([string]$selectedQuery.description)))[/]",
                        '',
                        "[darkred]Missing required context: $([string](Get-SpectreEscapedText (($selectedQueryResolution.MissingContext -join ', '))))[/]",
                        "[grey]Hint: $([string](Get-SpectreEscapedText ([string](& $getQueryContextGuidance $selectedQueryResolution.MissingContext[0]))))[/]"
                    )
                    $incidentDetails = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title 'Query Preview' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($blockedPreviewLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'incident_details' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'incident_details' -ActivePanel $activePanel) -Expand
                }
                elseif (-not [string]::IsNullOrWhiteSpace($selectedQueryPreviewError)) {
                    $incidentDetails = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title 'Query Preview' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data $selectedQueryPreviewError -Color (Get-PanelBorderColor -PanelName 'incident_details' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'incident_details' -ActivePanel $activePanel) -Expand
                }
                else {
                    $previewLines = @(
                        "[bold]$([string](Get-SpectreEscapedText ([string]$selectedQuery.name)))[/]",
                        "[grey]$([string](Get-SpectreEscapedText ([string]$selectedQuery.description)))[/]",
                        ''
                    )
                    if (@($selectedQuery.tags).Count -gt 0) {
                        $previewLines += "[grey]Tags: $([string](Get-SpectreEscapedText ((@($selectedQuery.tags) -join ', '))))[/]"
                        $previewLines += ''
                    }
                    $previewLines += "[white]$([string](Get-SpectreEscapedText ($selectedQueryPreview -replace "`r?`n", ' ')))[/]"
                    $incidentDetails = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title 'Query Preview' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($previewLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'incident_details' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'incident_details' -ActivePanel $activePanel) -Expand
                }

                $activityLines = @()
                if ($queryRunHistory.Count -eq 0) {
                    $activityLines += '[grey]No query runs recorded yet.[/]'
                }
                else {
                    foreach ($queryRun in @($queryRunHistory | Select-Object -First 6)) {
                        $statusColor = switch ([string]$queryRun.Status) {
                            'Success' { 'green' }
                            'NoResults' { 'yellow' }
                            default { 'red' }
                        }
                        $activityLines += "[bold $statusColor]$([string](Get-SpectreEscapedText ([string]$queryRun.Status)))[/] $([string](Get-SpectreEscapedText ([string]$queryRun.QueryName))) [grey]rows=$([int]$queryRun.RowCount) dur=$([int]$queryRun.DurationMs)ms[/]"
                    }
                }

                $alertsPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alerts' -Title "Activity Log ($($queryRunHistory.Count))" -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($activityLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'alerts' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'alerts' -ActivePanel $activePanel) -Expand

                $resultLines = @()
                if (-not $selectedQueryResult -or [string]$selectedQueryResult.QueryId -ne [string]$selectedQuery.id) {
                    $resultLines += '[grey]No results for the selected query yet. Use Alt+X to run it.[/]'
                }
                elseif ($selectedQueryResult.QueryRun.Status -eq 'NoResults') {
                    $resultLines += '[yellow]The last run completed successfully but returned no rows.[/]'
                }
                else {
                    $resultLines += "[grey]Rows: $([int]$selectedQueryResult.RowCount) | Duration: $([int]$selectedQueryResult.QueryRun.DurationMs)ms[/]"
                    $resultLines += ''
                    $resultColumns = @($selectedQuery.displayColumns)
                    if ($resultColumns.Count -gt 0) {
                        $resultLines += "[bold]$([string](Get-SpectreEscapedText (($resultColumns -join ' | '))))[/]"
                        foreach ($resultRow in @($selectedQueryResult.Results | Select-Object -First 8)) {
                            $resultValues = foreach ($resultColumn in $resultColumns) {
                                [string]$resultRow.$resultColumn
                            }
                            $resultLines += "[white]$([string](Get-SpectreEscapedText (($resultValues -join ' | '))))[/]"
                        }
                    }
                }

                $alertDetails = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Query Results' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($resultLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'alert_details' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'alert_details' -ActivePanel $activePanel) -Expand

                $queryExecuteReasons = @()
                $isQueryExecutionRunning = $queryExecutionJob -and $queryExecutionJob.State -notin @('Completed', 'Failed', 'Stopped')
                if (-not $selectedQuery) {
                    $queryExecuteReasons = @('No query selected')
                }
                elseif ($isQueryExecutionRunning) {
                    $queryExecuteReasons = @('Query execution in progress')
                }
                elseif ($selectedQueryResolution.IsBlocked) {
                    $queryExecuteReasons = @($selectedQueryResolution.MissingContext | ForEach-Object { "Missing $_" })
                }
                elseif (-not [string]::IsNullOrWhiteSpace($selectedQueryPreviewError)) {
                    $queryExecuteReasons = @($selectedQueryPreviewError)
                }

                $actionEntries = @(
                    [pscustomobject]@{ Shortcut = 'x'; Label = 'Execute selected query'; IsEnabled = ($queryExecuteReasons.Count -eq 0); Reasons = $queryExecuteReasons },
                    [pscustomobject]@{ Shortcut = 'h'; Label = 'Return to incident workflow'; IsEnabled = $true; Reasons = @() }
                )
                $selectedActionIndex = [Math]::Min([Math]::Max($selectedActionIndex, 0), $actionEntries.Count - 1)
                $queryActionLines = @(
                    'Query actions',
                    (New-ActionStateLine -Label '(Alt+X) Execute selected query' -Reasons $queryExecuteReasons),
                    '(Alt+H) Return to incident workflow'
                )

                if ($selectedEntity) {
                    $queryActionLines += ''
                    $queryActionLines += "Selected entity: $([string]$selectedEntity.EntityType) | $([string]$selectedEntity.DisplayName)"
                }

                if ($selectedQuery -and $selectedQueryResolution.IsBlocked) {
                    $queryActionLines += ''
                    $queryActionLines += "Missing context: $($selectedQueryResolution.MissingContext -join ', ')"
                    $queryActionLines += "Hint: $([string](& $getQueryContextGuidance $selectedQueryResolution.MissingContext[0]))"
                }

                if ($isQueryExecutionRunning) {
                    $queryActionLines += ''
                    $queryActionLines += 'Query execution is running in the background.'
                }

                $queryActionCursor = 0
                $queryActionDisplayLines = @($queryActionLines | ForEach-Object {
                    $line = [string]$_

                    if ([string]::IsNullOrWhiteSpace($line)) {
                        return ''
                    }

                    if ($line -eq 'Query actions') {
                        return "[bold grey]$(Get-SpectreEscapedText $line)[/]"
                    }

                    if ($line -match '^\(((?:Alt\+[A-Z])|ⓧ)\)\s+(.+)$') {
                        $shortcutSymbol = [string]$Matches[1]
                        $labelText = [string]$Matches[2]
                        $isEnabled = $shortcutSymbol -ne 'ⓧ'
                        $isSelected = ($activePanel -eq 'action_status' -and $queryActionCursor -eq $selectedActionIndex)
                        $queryActionCursor++

                        $prefix = if ($isSelected) { "[bold $($context.Ui.ThemeColor)]>[/] " } else { '  ' }
                        $shortcutMarkup = if ($isEnabled) {
                            if ($isSelected) { "[bold $($context.Ui.ThemeColor)]($shortcutSymbol)[/]" } else { "[bold deepskyblue1]($shortcutSymbol)[/]" }
                        }
                        else {
                            '[grey]([/][darkred]ⓧ[/][grey])[/]'
                        }

                        $escapedLabel = Get-SpectreEscapedText $labelText
                        $labelMarkup = if ($isEnabled) {
                            if ($isSelected) { "[bold $($context.Ui.ThemeColor)]$escapedLabel[/]" } else { "[white]$escapedLabel[/]" }
                        }
                        else {
                            if ($isSelected) { "[bold grey]$escapedLabel[/]" } else { "[grey]$escapedLabel[/]" }
                        }

                        return "$prefix$shortcutMarkup $labelMarkup"
                    }

                    return "  [grey]$(Get-SpectreEscapedText $line)[/]"
                })

                $actionStatusPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Query Actions' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($queryActionDisplayLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'action_status' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'action_status' -ActivePanel $activePanel) -Expand
            }

            $contextHelpLine = (Get-ContextAwareHelpLines -ActivePanel $activePanel -IsQueryMode:$isQueryMode -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation -PendingTextInput $pendingTextInput -PendingIncidentResolution $pendingIncidentResolution -PendingIncidentClassification $pendingIncidentClassification -PendingIncidentComment $pendingIncidentComment) -join ' | '
            $helpHeaderText = if ($showKeyboardHelpOverlay) { 'Help (F1 close)' } else { "Help | $contextHelpLine" }
            $helpPanel = Format-SpectrePanel -Header "[white]$helpHeaderText[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -SelectedIncident $selectedIncident -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -LastRefreshAt $lastDataRefreshAt -HeartbeatAt $lastHeartbeat -HeartbeatCounter $heartbeatCounter -IsQueryMode:$isQueryMode -ShowKeyboardHelpOverlay:$showKeyboardHelpOverlay) -Color (Get-PanelBorderColor -PanelName 'help' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'help' -ActivePanel $activePanel) -Expand

            $layout['header'].Update((Get-XdrLiveHeaderPanel -Context $context -ScriptRoot $PSScriptRoot)) | Out-Null
            $layout['incidents'].Update($incidentPanel) | Out-Null
            $layout['incident_details'].Update($incidentDetails) | Out-Null
            $layout['alerts'].Update($alertsPanel) | Out-Null
            $layout['alert_details'].Update($alertDetails) | Out-Null
            $layout['action_status'].Update($actionStatusPanel) | Out-Null
            $layout['help'].Update($helpPanel) | Out-Null
            $LiveContext.Refresh()

            Start-Sleep -Milliseconds $context.Ui.RefreshIntervalMs
        }
    }
}
