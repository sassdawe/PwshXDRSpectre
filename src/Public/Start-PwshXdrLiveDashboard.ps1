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

    # File logging is optional because the live TUI can run for a long time and should
    # stay quiet unless the operator asks for diagnostics.
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

    # Keep the global tab strip compact as the title of one bordered dashboard frame.
    $layout = New-XdrLiveDashboardLayout -ActionPanelVisible

    $dashboardFrame = Format-SpectrePanel -Data $layout -Header ' ' -Color 'deepskyblue1' -Border 'Rounded' -Expand
    $screenLayout = New-SpectreLayout -Name 'screen' -Rows @(
        (New-SpectreLayout -Name 'dashboard_frame' -Ratio 1 -Data $dashboardFrame)
    )

    Invoke-SpectreLive -Data $screenLayout -ScriptBlock {
        param([Spectre.Console.LiveDisplayContext]$LiveContext)

        # The Spectre live callback owns all mutable TUI state. Helper functions receive
        # [ref] parameters when they need to update these local selections.

        # Global tab bar configuration
        $tabOrder = @('welcome', 'incidents', 'hunting', 'query_library', 'quarantine', 'action_center', 'settings', 'help')
        $activeTabIndex = 1 # default to 'incidents'
        $activeTab = $tabOrder[$activeTabIndex]
        $context.Selection.Tab = $activeTab
        $actionStatusPanelVisible = $true

        # Render global tab header
        Update-XdrLiveOuterTabs -DashboardFrame $dashboardFrame -ScreenLayout $screenLayout -TabOrder $tabOrder -ActiveTabIndex $activeTabIndex

        # Authentication and data-loading flags gate the early render states before the
        # normal incident/action panels can be built.
        $authAttempted = $false
        $authSucceeded = $false
        $dataLoaded = $false
        $fatalErrorMessage = $null

        $panelOrder = @(Get-XdrLivePanelOrder -TabName $activeTab -HideActionPanel:(-not $actionStatusPanelVisible))
        $selectedIncidentDetailsTab = 'details'  # 'details' or 'entities'
        $activePanelIndex = 0
        $activePanel = $panelOrder[$activePanelIndex]
        $context.Selection.Panel = $activePanel



        # Selection state is deliberately separate from the data caches so navigation can
        # preserve the current incident/alert while background refresh jobs complete.
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
        # Background job and cache state. Alert and entity loads are folded back into the
        # UI loop instead of blocking keyboard input or Spectre refresh.
        $alertsByIncidentId = @{}
        $entitiesByIncidentId = @{}
        $entityAlertCountByIncidentId = @{}
        $selectedAlertIdByIncidentId = @{}
        $alertLoadJobsByIncidentId = @{}
        $entityLoadJobsByIncidentId = @{}
        $alertPreloadQueue = [System.Collections.Queue]::new()
        $maxAlertLoadJobs = 2
        $prefetchCompletedAt = $null
        $lastLoopHealthLogAt = [datetime]::MinValue
        $lastLoopStartedAt = [datetime]::MinValue
        $modulePath = Join-Path $PSScriptRoot '..' 'PwshXDRSpectre.psm1'
        $triageOptions = Get-XdrTriageOptions
        $autoRefreshInterval = [timespan]::FromMinutes(3)
        $lastDataRefreshAt = $null
        $pendingRefreshIncidentId = $null
        $pendingRefreshAlertId = $null
        $pendingRefreshEntityKey = $null
        $lastHeartbeat = Get-Date
        $heartbeatCounter = 0
        $incidentLoadJob = $null
        $queryExecutionJob = $null
        $queryResultsByCacheKey = @{}

        # Load the hunting catalog up front; query execution itself still runs in the
        # background so slow Defender queries do not freeze the dashboard loop.
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

        while ($true) {
            # Throttle at the top so every branch, including those that continue before
            # the render tail, still yields time back to the terminal and input system.
            if ($lastLoopStartedAt -ne [datetime]::MinValue) {
                $loopElapsedMs = [int]((Get-Date) - $lastLoopStartedAt).TotalMilliseconds
                $remainingDelayMs = [int]$context.Ui.RefreshIntervalMs - $loopElapsedMs
                if ($remainingDelayMs -gt 0) {
                    Start-Sleep -Milliseconds $remainingDelayMs
                }
            }
            $lastLoopStartedAt = Get-Date

            # Update heartbeat on every iteration to show dashboard is responsive
            $lastHeartbeat = Get-Date
            $heartbeatCounter++
            if ($lastLoopHealthLogAt -eq [datetime]::MinValue -or (Get-Date) -ge $lastLoopHealthLogAt.AddSeconds(5)) {
                Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message "Loop heartbeat. Count=$heartbeatCounter ActiveTab=$activeTab ActivePanel=$activePanel DataLoaded=$dataLoaded AlertJobs=$($alertLoadJobsByIncidentId.Count) EntityJobs=$($entityLoadJobsByIncidentId.Count)"
                $lastLoopHealthLogAt = Get-Date
            }

            $statusExpiresAtProperty = $context.Ui.PSObject.Properties['StatusExpiresAt']
            if ($statusExpiresAtProperty -and $statusExpiresAtProperty.Value -is [datetime]) {
                if ((Get-Date) -ge [datetime]$statusExpiresAtProperty.Value) {
                    $context.Ui.StatusMessage = $null
                    $context.Ui.StatusExpiresAt = $null
                }
            }

            # Capture keys before any loading/authentication branch can continue.
            $rawKeys = if (
                $isQueryMode -or
                $null -ne $pendingTextInput -or
                ($null -ne $pendingIncidentComment -and [string]$pendingIncidentComment.Step -eq 'comment') -or
                ($null -ne $pendingIncidentResolution -and [string]$pendingIncidentResolution.Step -eq 'comment')
            ) {
                @(Get-XdrAllKeysPressed)
            }
            else {
                $lastKey = Get-XdrLastKeyPressed
                if ($null -ne $lastKey) { @($lastKey) } else { @() }
            }

            # Global shortcuts are handled before loading/auth branches. Unhandled keys
            # are queued for the mode-specific handler after data and cache state settle.
            $keysForMainHandler = [System.Collections.Generic.List[System.ConsoleKeyInfo]]::new()
            foreach ($earlyKey in $rawKeys) {
                if ($null -eq $earlyKey) { continue }

                $earlyInputTime = Get-Date
                $earlyKeyChar = ([string]$earlyKey.KeyChar).ToLowerInvariant()
                $earlyShiftPressed = (($earlyKey.Modifiers -band [ConsoleModifiers]::Shift) -ne 0)
                $earlyCtrlPressed = (($earlyKey.Modifiers -band [ConsoleModifiers]::Control) -ne 0)
                $earlyAltPressed = (($earlyKey.Modifiers -band [ConsoleModifiers]::Alt) -ne 0)
                $earlyModifierLabels = @()
                if ($earlyCtrlPressed) { $earlyModifierLabels += 'Ctrl' }
                if ($earlyAltPressed) { $earlyModifierLabels += 'Alt' }
                if ($earlyShiftPressed) { $earlyModifierLabels += 'Shift' }
                $earlyModifierSummary = if ($earlyModifierLabels.Count -gt 0) { $earlyModifierLabels -join '+' } else { 'None' }
                $earlyKeyCharDisplay = if ([char]$earlyKey.KeyChar -eq [char]0) { '' } else { [string]$earlyKey.KeyChar }
                $earlyKeyHandled = $false

                if ($pendingQuitConfirmation) {
                    $earlyKeyHandled = $true
                    if ((-not $earlyAltPressed -and -not $earlyCtrlPressed -and $earlyKeyChar -eq 'y') -or $earlyKey.Key -eq 'Enter') {
                        return
                    }

                    if ((-not $earlyAltPressed -and -not $earlyCtrlPressed -and $earlyKeyChar -eq 'n') -or $earlyKey.Key -eq 'Escape') {
                        $pendingQuitConfirmation = $false
                        Set-LiveStatusMessage -Context $context -Message 'Quit canceled.' -Level 'info'
                    }
                }
                elseif ($earlyKey.Key -eq 'F1') {
                    $earlyKeyHandled = $true
                    $showKeyboardHelpOverlay = -not $showKeyboardHelpOverlay
                    if ($showKeyboardHelpOverlay) {
                        Set-LiveStatusMessage -Context $context -Message 'Keyboard help overlay enabled (F1 to close).' -Level 'info'
                    }
                    else {
                        Set-LiveStatusMessage -Context $context -Message 'Keyboard help overlay closed.' -Level 'info'
                    }
                }
                elseif (Test-XdrConsoleShortcut -Key $earlyKey -KeyName 'k' -Alt -Control) {
                    $earlyKeyHandled = $true
                    $context.Diagnostics.InputDebugEnabled = -not $context.Diagnostics.InputDebugEnabled
                    if ($context.Diagnostics.InputDebugEnabled) {
                        Set-LiveStatusMessage -Context $context -Message 'Input debug enabled (Ctrl+Alt+K). Check the help panel for last key and query state.' -Level 'info'
                    }
                    else {
                        Set-LiveStatusMessage -Context $context -Message 'Input debug disabled (Ctrl+Alt+K).' -Level 'info'
                    }
                }
                elseif (Test-XdrConsoleShortcut -Key $earlyKey -KeyName 'a' -Alt -Control) {
                    $earlyKeyHandled = $true
                    $actionStatusPanelVisible = -not $actionStatusPanelVisible
                    Set-XdrLiveActionPanelVisibility -Visible $actionStatusPanelVisible -Layout ([ref]$layout) -DashboardFrame ([ref]$dashboardFrame) -ScreenLayout $screenLayout -TabOrder $tabOrder -ActiveTabIndex $activeTabIndex -ActiveTab $activeTab -PanelOrder ([ref]$panelOrder) -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -Context $context
                    $layoutModeMessage = if ($actionStatusPanelVisible) { 'Action Status panel shown. Restored three-column layout.' } else { 'Action Status panel hidden. Switched to 50-50 compact layout.' }
                    Set-LiveStatusMessage -Context $context -Message $layoutModeMessage -Level 'info'
                }
                elseif ((-not $earlyAltPressed -and -not $earlyCtrlPressed -and $earlyKeyChar -eq 'q') -or ($earlyCtrlPressed -and -not $earlyAltPressed -and $earlyKeyChar -eq 'q')) {
                    $earlyKeyHandled = $true
                    $pendingQuitConfirmation = $true
                    Set-LiveStatusMessage -Context $context -Message 'Quit dashboard? Press Y to confirm, N or Esc to continue.' -Level 'warning'
                }
                elseif ($earlyAltPressed -and $earlyKeyChar -in @('1', '2', '3', '4', '5', '6', '7', '8')) {
                    $earlyKeyHandled = $true
                    $tabIndex = [int]::Parse($earlyKeyChar) - 1
                    if ($tabIndex -ge 0 -and $tabIndex -lt $tabOrder.Count) {
                        Set-XdrLiveActiveTab -TabName $tabOrder[$tabIndex] -TabOrder $tabOrder -PanelOrder ([ref]$panelOrder) -Context $context -ActiveTabIndex ([ref]$activeTabIndex) -ActiveTab ([ref]$activeTab) -IsQueryMode ([ref]$isQueryMode) -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -SelectedActionIndex ([ref]$selectedActionIndex) -SelectedQueryIndex ([ref]$selectedQueryIndex) -SelectedQuery ([ref]$selectedQuery) -SelectedQueryResult ([ref]$selectedQueryResult) -QueryResultsByCacheKey $queryResultsByCacheKey -HideActionPanel:(-not $actionStatusPanelVisible)
                        Set-LiveStatusMessage -Context $context -Message "Switched to tab: $activeTab" -Level 'info'
                    }
                }
                elseif (($earlyKey.Key -eq 'F5' -or (-not $earlyAltPressed -and -not $earlyCtrlPressed -and $earlyKeyChar -eq 'r')) -and $authSucceeded) {
                    $earlyKeyHandled = $true
                    Reset-XdrLiveDashboardDataForRefresh -Context $context -ReasonMessage 'Refreshing incidents and alert cache...' -PreserveSelection $true -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -SelectedEntity $selectedEntity -PendingRefreshIncidentId ([ref]$pendingRefreshIncidentId) -PendingRefreshAlertId ([ref]$pendingRefreshAlertId) -PendingRefreshEntityKey ([ref]$pendingRefreshEntityKey) -DataLoaded ([ref]$dataLoaded) -IncidentLoadJob ([ref]$incidentLoadJob) -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -EntityLoadJobsByIncidentId $entityLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -SelectedIndex ([ref]$selectedIndex) -SelectedAlertIndex ([ref]$selectedAlertIndex) -SelectedEntityIndex ([ref]$selectedEntityIndex) -SelectedIncidentRef ([ref]$selectedIncident) -SelectedAlertRef ([ref]$selectedAlert) -SelectedEntityRef ([ref]$selectedEntity) -AlertsByIncidentId $alertsByIncidentId -EntitiesByIncidentId $entitiesByIncidentId -EntityAlertCountByIncidentId $entityAlertCountByIncidentId -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -LogPath $dashboardLogPath
                }

                if ($earlyKeyHandled) {
                    Set-XdrLastInputDiagnostics -Context $context -Key $earlyKey -InputTime $earlyInputTime -KeyCharDisplay $earlyKeyCharDisplay -ModifierSummary $earlyModifierSummary -KeyHandled $true -ActivePanel $activePanel -IsQueryMode $isQueryMode -SelectedQueryIndex $selectedQueryIndex -SelectedQuery $selectedQuery -SelectedEntity $selectedEntity
                }
                else {
                    [void]$keysForMainHandler.Add($earlyKey)
                }
            }

            Update-XdrLiveOuterTabs -DashboardFrame $dashboardFrame -ScreenLayout $screenLayout -TabOrder $tabOrder -ActiveTabIndex $activeTabIndex

            $incidentDetailsHeader = Get-XdrIncidentDetailsTabHeader -CurrentTab $selectedIncidentDetailsTab

            #region authentication
            # Authentication is performed once from inside the live loop so the operator
            # sees progress and can still receive a rendered failure screen.
            if (-not $authAttempted) {
                Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message 'Authentication sequence started.'
                Update-XdrLiveOuterTabs -DashboardFrame $dashboardFrame -ScreenLayout $screenLayout -TabOrder $tabOrder -ActiveTabIndex $activeTabIndex

                if ($activeTab -eq 'incidents') {
                    $layout['left_top'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_list' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
                    $layout['center_top'].Update((Format-SpectrePanel -Header $incidentDetailsHeader -Data 'Preparing authentication...' -Expand)) | Out-Null
                    $layout['left_bottom'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_list' -Title 'Alert List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
                    $layout['center_bottom'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
                    if ($actionStatusPanelVisible) { $layout['right_actions'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_actions' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null }
                }

                $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -SelectedIncident $selectedIncident -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -LastRefreshAt $lastDataRefreshAt -HeartbeatAt $lastHeartbeat -HeartbeatCounter $heartbeatCounter) -Expand)) | Out-Null
                $LiveContext.Refresh()

                $authAttempted = $true
                if ($activeTab -eq 'incidents') {
                    $layout['left_top'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_list' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Authenticating with Microsoft Graph...' -Expand)) | Out-Null
                    $layout['center_top'].Update((Format-SpectrePanel -Header $incidentDetailsHeader -Data 'Authenticating with Microsoft Graph...' -Expand)) | Out-Null
                    if ($actionStatusPanelVisible) { $layout['right_actions'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_actions' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Authenticating with Microsoft Graph...' -Expand)) | Out-Null }
                }
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
                $layout['left_top'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_list' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No incidents found. Press Ctrl+C to exit.' -Expand)) | Out-Null
                $layout['center_top'].Update((Format-SpectrePanel -Header '[red]Authentication Failed[/]' -Data $fatalErrorMessage -Expand)) | Out-Null
                $layout['left_bottom'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_list' -Title 'Alert List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No data available.' -Expand)) | Out-Null
                $layout['center_bottom'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No data available.' -Expand)) | Out-Null
                if ($actionStatusPanelVisible) { $layout['right_actions'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_actions' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No actions available.' -Expand)) | Out-Null }
                $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -SelectedIncident $selectedIncident -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -LastRefreshAt $lastDataRefreshAt -HeartbeatAt $lastHeartbeat -HeartbeatCounter $heartbeatCounter) -Expand)) | Out-Null
                $LiveContext.Refresh()

                $keyOnError = Get-XdrLastKeyPressed
                if ($keyOnError -and $keyOnError.Key -eq 'Escape') {
                    return
                }

                Start-Sleep -Milliseconds $context.Ui.RefreshIntervalMs
                continue
            }
            #endregion authentication

            # Incident loading is asynchronous; while it runs, keep refreshing help and
            # non-incident tabs instead of blocking on Microsoft Graph.
            if (-not $dataLoaded) {
                $hasVisibleIncidentData = @($context.Data.Incidents).Count -gt 0
                if (-not $incidentLoadJob) {
                    Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message 'Starting background incident load.'
                    $incidentLoadJob = Start-XdrLiveIncidentLoadJob -ModulePath $modulePath -Context $context -Limit $Limit -LogPath $dashboardLogPath
                    Set-LiveStatusMessage -Context $context -Message 'Loading incidents in the background...' -Level 'info'
                }

                if ($incidentLoadJob -and $incidentLoadJob.State -in @('Completed', 'Failed', 'Stopped')) {
                    $incidentJobState = [string]$incidentLoadJob.State
                    $incidentJobOutput = Receive-Job -Job $incidentLoadJob -ErrorAction SilentlyContinue
                    Remove-Job -Job $incidentLoadJob -Force -ErrorAction SilentlyContinue
                    $incidentLoadJob = $null

                    if ($incidentJobState -ne 'Completed') {
                        $fatalErrorMessage = "Incident load job ended unexpectedly: $incidentJobState"
                        Set-LiveStatusMessage -Context $context -Message $fatalErrorMessage -Level 'error'
                        Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message $fatalErrorMessage -Level 'ERROR'
                        continue
                    }

                    $incidentsResult = $incidentJobOutput | Select-Object -Last 1 -ExpandProperty Result -ErrorAction SilentlyContinue
                    if (-not $incidentsResult -or -not $incidentsResult.Success) {
                        $fatalErrorMessage = if ($incidentsResult) { [string]$incidentsResult.Message } else { 'Incident load job did not return a result.' }
                        Set-LiveStatusMessage -Context $context -Message $fatalErrorMessage -Level 'error'
                        Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message "Initial incident load failed while authentication state was preserved: $fatalErrorMessage" -Level 'ERROR'
                        continue
                    }

                    $context.Data.Incidents = @($incidentsResult.Data)
                    $context.Data.LastRefresh = Get-Date
                    $dataLoaded = $true
                    $lastDataRefreshAt = Get-Date
                    Sync-XdrLiveCachedDataToIncidents -Incidents $context.Data.Incidents -CacheTables @($alertsByIncidentId, $entitiesByIncidentId, $entityAlertCountByIncidentId, $selectedAlertIdByIncidentId)
                    Add-XdrLiveAlertPreloads -Incidents $context.Data.Incidents -AlertPreloadQueue $alertPreloadQueue -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId
                    Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message "Initial incident load completed. IncidentCount=$(@($context.Data.Incidents).Count)"
                    if ($context.Data.Incidents.Count -gt 0) {
                        $selectedIndex = [Math]::Min([Math]::Max($selectedIndex, 0), $context.Data.Incidents.Count - 1)
                        if (-not [string]::IsNullOrWhiteSpace([string]$pendingRefreshIncidentId)) {
                            $pendingIncidentRestored = $false
                            for ($incidentCursor = 0; $incidentCursor -lt $context.Data.Incidents.Count; $incidentCursor++) {
                                if ([string]$context.Data.Incidents[$incidentCursor].IncidentId -eq [string]$pendingRefreshIncidentId) {
                                    $selectedIndex = $incidentCursor
                                    $pendingIncidentRestored = $true
                                    break
                                }
                            }
                            Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message "Refresh incident selection restore. IncidentId=$pendingRefreshIncidentId Restored=$pendingIncidentRestored SelectedIndex=$selectedIndex"
                        }
                    }
                }
                else {
                    Update-XdrLiveOuterTabs -DashboardFrame $dashboardFrame -ScreenLayout $screenLayout -TabOrder $tabOrder -ActiveTabIndex $activeTabIndex
                    $helpPanel = Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -SelectedIncident $selectedIncident -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -LastRefreshAt $lastDataRefreshAt -HeartbeatAt $lastHeartbeat -HeartbeatCounter $heartbeatCounter -IsQueryMode:$isQueryMode -ShowKeyboardHelpOverlay:$showKeyboardHelpOverlay) -Expand
                    if ($activeTab -eq 'incidents') {
                        if (-not $hasVisibleIncidentData) {
                            $loadingMessage = "Loading incidents... heartbeat $heartbeatCounter"
                            $layout['left_top'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_list' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Loading incidents...' -Expand)) | Out-Null
                            $layout['center_top'].Update((Format-SpectrePanel -Header $incidentDetailsHeader -Data $loadingMessage -Expand)) | Out-Null
                            $layout['left_bottom'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_list' -Title 'Alert List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Waiting for incident load to finish...' -Expand)) | Out-Null
                            $layout['center_bottom'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Waiting for incident load to finish...' -Expand)) | Out-Null
                            if ($actionStatusPanelVisible) { $layout['right_actions'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_actions' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Loading capabilities...' -Expand)) | Out-Null }
                        }
                        $layout['help'].Update($helpPanel) | Out-Null
                    }
                    else {
                        Show-XdrLiveNonIncidentTab -Layout $layout -ActiveTab $activeTab -ActivePanel $activePanel -Context $context -CurrentHelpPanel $helpPanel -DashboardLogPath $dashboardLogPath -TenantId $TenantId -ClientId $ClientId -SelectedIncident $selectedIncident -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -LastRefreshAt $lastDataRefreshAt -HeartbeatAt $lastHeartbeat -HeartbeatCounter $heartbeatCounter -IsQueryMode $isQueryMode -ShowKeyboardHelpOverlay $showKeyboardHelpOverlay -ActionPanelVisible $actionStatusPanelVisible
                    }

                    $LiveContext.Refresh()
                    continue
                }
                # After a successful incident load, restore whatever cached alert/entity
                # state matches the selected incident before the first full render.
                $selectedIncident = $context.Data.Incidents[$selectedIndex]
                $context.Selection.Incident = $selectedIncident
                if ($entitiesByIncidentId.ContainsKey([string]$selectedIncident.IncidentId)) {
                    $context.Data.Entities = @($entitiesByIncidentId[[string]$selectedIncident.IncidentId])
                }
                else {
                    $context.Data.Entities = @()
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$pendingRefreshEntityKey) -and $context.Data.Entities.Count -gt 0) {
                    Restore-XdrLiveEntitySelection -Context $context -EntitySelectionKey $pendingRefreshEntityKey -SelectedEntity ([ref]$selectedEntity) -SelectedEntityIndex ([ref]$selectedEntityIndex) | Out-Null
                    $pendingRefreshEntityKey = $null
                }
                else {
                    $selectedEntityIndex = 0
                    $selectedEntity = $null
                    $context.Selection.Entity = $null
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$pendingRefreshAlertId)) {
                    $selectedAlertIdByIncidentId[[string]$selectedIncident.IncidentId] = [string]$pendingRefreshAlertId
                }
                if (-not (Restore-XdrLiveCachedAlertsForIncident -IncidentId ([string]$selectedIncident.IncidentId) -AlertsByIncidentId $alertsByIncidentId -Context $context -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex) -LogPath $dashboardLogPath)) {
                    $selectedAlert = $null
                    $selectedAlertIndex = 0
                    $context.Selection.Alert = $null
                    $context.Data.Alerts = @()
                    Clear-XdrLiveVisibleAlerts -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId)
                    Set-LiveStatusMessage -Context $context -Message 'Press Enter to load alerts for the selected incident.' -Level 'info'
                }
                else {
                    Sync-XdrLiveVisibleAlertsFromContext -Context $context -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -Incident $selectedIncident
                }
            }
            elseif (@($context.Data.Incidents).Count -gt 0) {
                $selectedIndex = [Math]::Min([Math]::Max($selectedIndex, 0), @($context.Data.Incidents).Count - 1)
                if (-not $selectedIncident) {
                    $selectedIncident = $context.Data.Incidents[$selectedIndex]
                    $context.Selection.Incident = $selectedIncident
                }
            }
            else {
                $context.Data.Alerts = @()
                $context.Data.Entities = @()
                Clear-XdrLiveVisibleAlerts -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId)
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

            # Do not auto-refresh while the user is midway through a modal workflow; those
            # flows keep transient input that would be confusing to discard underneath them.
            $autoRefreshBlocked =
            ($null -ne $pendingIncidentResolution) -or
            ($null -ne $pendingIncidentClassification) -or
            ($null -ne $pendingIncidentComment) -or
            ($null -ne $pendingTextInput) -or
            ($null -ne $pendingConfirmation)

            if (-not $autoRefreshBlocked -and $null -ne $lastDataRefreshAt -and (Get-Date) -ge $lastDataRefreshAt.Add($autoRefreshInterval)) {
                Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message "Auto-refresh triggered after $autoRefreshInterval. IncidentCount=$(@($context.Data.Incidents).Count)"
                Reset-XdrLiveDashboardDataForRefresh -Context $context -ReasonMessage 'Auto-refreshing incidents and alerts (every 3 minutes)...' -PreserveSelection $true -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -SelectedEntity $selectedEntity -PendingRefreshIncidentId ([ref]$pendingRefreshIncidentId) -PendingRefreshAlertId ([ref]$pendingRefreshAlertId) -PendingRefreshEntityKey ([ref]$pendingRefreshEntityKey) -DataLoaded ([ref]$dataLoaded) -IncidentLoadJob ([ref]$incidentLoadJob) -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -EntityLoadJobsByIncidentId $entityLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -SelectedIndex ([ref]$selectedIndex) -SelectedAlertIndex ([ref]$selectedAlertIndex) -SelectedEntityIndex ([ref]$selectedEntityIndex) -SelectedIncidentRef ([ref]$selectedIncident) -SelectedAlertRef ([ref]$selectedAlert) -SelectedEntityRef ([ref]$selectedEntity) -AlertsByIncidentId $alertsByIncidentId -EntitiesByIncidentId $entitiesByIncidentId -EntityAlertCountByIncidentId $entityAlertCountByIncidentId -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -LogPath $dashboardLogPath
                continue
            }

            # Fold completed alert/query/entity jobs back into the single-threaded render
            # state. This keeps all Spectre updates on the live loop.
            Invoke-XdrLiveAlertLoadJobProcessing -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertsByIncidentId $alertsByIncidentId -SelectedIncident $selectedIncident -Context $context -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex) -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -LogPath $dashboardLogPath
            if ($dataLoaded) {
                Start-XdrLiveQueuedAlertPreloads -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -MaxAlertLoadJobs $maxAlertLoadJobs -AlertPreloadQueue $alertPreloadQueue -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId -LogPath $dashboardLogPath
            }
            Invoke-XdrLiveQueryJobProcessing -QueryJob ([ref]$queryExecutionJob) -QueryResultsByCacheKey $queryResultsByCacheKey -Context $context -SelectedQuery $selectedQuery -SelectedQueryResult ([ref]$selectedQueryResult)

            if ($selectedIncident) {
                # Cached alerts can change without the incident id or count changing, so
                # compare a stable signature before deciding the visible list is current.
                $selectedIncidentId = [string]$selectedIncident.IncidentId
                if (-not [string]::IsNullOrWhiteSpace($selectedIncidentId) -and $alertsByIncidentId.ContainsKey($selectedIncidentId)) {
                    $cachedAlertsForSelectedIncident = @($alertsByIncidentId[$selectedIncidentId])
                    $visibleAlertSignature = Get-XdrAlertListSignature -Alerts @($visibleAlerts)
                    $cachedAlertSignature = Get-XdrAlertListSignature -Alerts $cachedAlertsForSelectedIncident
                    if ([string]$visibleAlertIncidentId -ne $selectedIncidentId -or @($visibleAlerts).Count -ne $cachedAlertsForSelectedIncident.Count -or $visibleAlertSignature -ne $cachedAlertSignature) {
                        Restore-XdrLiveCachedAlertsForIncident -IncidentId $selectedIncidentId -AlertsByIncidentId $alertsByIncidentId -Context $context -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex) -LogPath $dashboardLogPath | Out-Null
                        Sync-XdrLiveVisibleAlertsFromContext -Context $context -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -Incident $selectedIncident
                    }
                }
            }

            # Entity extraction jobs are keyed by incident id so stale completions cannot
            # overwrite the visible entities for a different selected incident.
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

                if (-not [string]::IsNullOrWhiteSpace([string]$pendingRefreshEntityKey) -and $context.Data.Entities.Count -gt 0) {
                    Restore-XdrLiveEntitySelection -Context $context -EntitySelectionKey $pendingRefreshEntityKey -SelectedEntity ([ref]$selectedEntity) -SelectedEntityIndex ([ref]$selectedEntityIndex) | Out-Null
                    $pendingRefreshEntityKey = $null
                }

                $cachedAlertCount = if ($entityAlertCountByIncidentId.ContainsKey($selectedIncidentId)) { [int]$entityAlertCountByIncidentId[$selectedIncidentId] } else { -1 }
                if ($selectedIncidentDetailsTab -eq 'entities' -and $cachedAlertCount -ne $selectedIncidentAlertCount -and -not $entityLoadJobsByIncidentId.ContainsKey($selectedIncidentId)) {
                    Start-XdrLiveEntityExtraction -Incident $selectedIncident -EntityLoadJobsByIncidentId $entityLoadJobsByIncidentId -AlertsByIncidentId $alertsByIncidentId -ModulePath $modulePath -DashboardLogPath $dashboardLogPath
                }
            }

            #region wizard focus pinning
            # Wizard-style workflows pin focus to the action panel until they complete or
            # cancel, even if the user was previously navigating another panel.
            if (($null -ne $pendingIncidentResolution -or $null -ne $pendingIncidentClassification -or $null -ne $pendingIncidentComment) -and -not $actionStatusPanelVisible) {
                $actionStatusPanelVisible = $true
                Set-XdrLiveActionPanelVisibility -Visible $actionStatusPanelVisible -Layout ([ref]$layout) -DashboardFrame ([ref]$dashboardFrame) -ScreenLayout $screenLayout -TabOrder $tabOrder -ActiveTabIndex $activeTabIndex -ActiveTab $activeTab -PanelOrder ([ref]$panelOrder) -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -Context $context
                Set-LiveStatusMessage -Context $context -Message 'Action Status panel shown for the active workflow.' -Level 'info'
            }

            if ($null -ne $pendingIncidentResolution) {
                $activePanel = 'incident_actions'
                $activePanelIndex = [array]::IndexOf($panelOrder, 'incident_actions')
                $context.Selection.Panel = $activePanel
            }
            elseif ($null -ne $pendingIncidentClassification) {
                $activePanel = 'incident_actions'
                $activePanelIndex = [array]::IndexOf($panelOrder, 'incident_actions')
                $context.Selection.Panel = $activePanel
            }
            elseif ($null -ne $pendingIncidentComment) {
                $activePanel = 'incident_actions'
                $activePanelIndex = [array]::IndexOf($panelOrder, 'incident_actions')
                $context.Selection.Panel = $activePanel
            }
            #endregion wizard focus pinning

            # Main input handler: modal workflows get first chance, then global navigation,
            # then mode-specific movement/actions for incidents or hunting.
            foreach ($key in @($keysForMainHandler)) {
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
                if ($context.Diagnostics.InputDebugEnabled -and $isQueryMode) {
                    Write-XdrLiveDashboardLog -LogPath $dashboardLogPath -Message "InputDebug Key=$([string]$key.Key) Char=$keyCharDisplay Modifiers=$modifierSummary Panel=$activePanel QueryMode=$isQueryMode QueryIndex=$selectedQueryIndex QueryId=$(if ($selectedQuery) { [string]$selectedQuery.id } else { '' }) Entity=$(if ($selectedEntity) { [string]$selectedEntity.DisplayName } else { '' })"
                }

                try {
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
                    elseif (Test-XdrConsoleShortcut -Key $key -KeyName 'k' -Alt -Control) {
                        $keyHandled = $true
                        $context.Diagnostics.InputDebugEnabled = -not $context.Diagnostics.InputDebugEnabled
                        if ($context.Diagnostics.InputDebugEnabled) {
                            Set-LiveStatusMessage -Context $context -Message 'Input debug enabled (Ctrl+Alt+K). Check the help panel for last key and query state.' -Level 'info'
                        }
                        else {
                            Set-LiveStatusMessage -Context $context -Message 'Input debug disabled (Ctrl+Alt+K).' -Level 'info'
                        }
                    }
                    elseif (Test-XdrConsoleShortcut -Key $key -KeyName 'a' -Alt -Control) {
                        $keyHandled = $true
                        $actionStatusPanelVisible = -not $actionStatusPanelVisible
                        Set-XdrLiveActionPanelVisibility -Visible $actionStatusPanelVisible -Layout ([ref]$layout) -DashboardFrame ([ref]$dashboardFrame) -ScreenLayout $screenLayout -TabOrder $tabOrder -ActiveTabIndex $activeTabIndex -ActiveTab $activeTab -PanelOrder ([ref]$panelOrder) -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -Context $context
                        $layoutModeMessage = if ($actionStatusPanelVisible) { 'Action Status panel shown. Restored three-column layout.' } else { 'Action Status panel hidden. Switched to 50-50 compact layout.' }
                        Set-LiveStatusMessage -Context $context -Message $layoutModeMessage -Level 'info'
                    }
                    elseif ((-not $isAltPressed -and -not $isCtrlPressed -and $keyChar -eq 'q') -or ($isCtrlPressed -and -not $isAltPressed -and $keyChar -eq 'q')) {
                        $keyHandled = $true
                        $pendingQuitConfirmation = $true
                        Set-LiveStatusMessage -Context $context -Message 'Quit dashboard? Press Y to confirm, N or Esc to continue.' -Level 'warning'
                    }
                    elseif ($isAltPressed -and $keyChar -in @('1', '2', '3', '4', '5', '6', '7', '8')) {
                        $keyHandled = $true
                        $index = [int]::Parse($keyChar) - 1
                        if ($index -ge 0 -and $index -lt $tabOrder.Count) {
                            Set-XdrLiveActiveTab -TabName $tabOrder[$index] -TabOrder $tabOrder -PanelOrder ([ref]$panelOrder) -Context $context -ActiveTabIndex ([ref]$activeTabIndex) -ActiveTab ([ref]$activeTab) -IsQueryMode ([ref]$isQueryMode) -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -SelectedActionIndex ([ref]$selectedActionIndex) -SelectedQueryIndex ([ref]$selectedQueryIndex) -SelectedQuery ([ref]$selectedQuery) -SelectedQueryResult ([ref]$selectedQueryResult) -QueryResultsByCacheKey $queryResultsByCacheKey -HideActionPanel:(-not $actionStatusPanelVisible)
                            Set-LiveStatusMessage -Context $context -Message "Switched to tab: $activeTab" -Level 'info'
                        }
                    }
                    elseif ($isAltPressed -and $keyChar -eq 'e') {
                        if ($selectedIncident) {
                            $selectedIncidentDetailsTab = 'entities'
                            $activePanel = 'incident_details'
                            $activePanelIndex = [array]::IndexOf($panelOrder, 'incident_details')
                            $context.Selection.Panel = $activePanel
                            if ($selectedIncidentDetailsTab -eq 'entities' -and $selectedIncident) { Start-XdrLiveEntityExtraction -Incident $selectedIncident -EntityLoadJobsByIncidentId $entityLoadJobsByIncidentId -AlertsByIncidentId $alertsByIncidentId -ModulePath $modulePath -DashboardLogPath $dashboardLogPath }
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
                        if ($activeTab -eq 'hunting') {
                            Set-XdrLiveActiveTab -TabName 'incidents' -TabOrder $tabOrder -PanelOrder ([ref]$panelOrder) -Context $context -ActiveTabIndex ([ref]$activeTabIndex) -ActiveTab ([ref]$activeTab) -IsQueryMode ([ref]$isQueryMode) -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -SelectedActionIndex ([ref]$selectedActionIndex) -SelectedQueryIndex ([ref]$selectedQueryIndex) -SelectedQuery ([ref]$selectedQuery) -SelectedQueryResult ([ref]$selectedQueryResult) -QueryResultsByCacheKey $queryResultsByCacheKey -HideActionPanel:(-not $actionStatusPanelVisible)
                            Set-LiveStatusMessage -Context $context -Message 'Returned to incident workflow.' -Level 'info'
                        }
                        else {
                            Set-XdrLiveActiveTab -TabName 'hunting' -TabOrder $tabOrder -PanelOrder ([ref]$panelOrder) -Context $context -ActiveTabIndex ([ref]$activeTabIndex) -ActiveTab ([ref]$activeTab) -IsQueryMode ([ref]$isQueryMode) -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -SelectedActionIndex ([ref]$selectedActionIndex) -SelectedQueryIndex ([ref]$selectedQueryIndex) -SelectedQuery ([ref]$selectedQuery) -SelectedQueryResult ([ref]$selectedQueryResult) -QueryResultsByCacheKey $queryResultsByCacheKey -HideActionPanel:(-not $actionStatusPanelVisible)
                            Set-LiveStatusMessage -Context $context -Message 'Switched to Hunting tab. Use the query catalog on the left and Alt+X to execute.' -Level 'info'
                        }
                    }
                    elseif ($isQueryMode -and $isAltPressed -and $keyChar -eq 'x') {
                        $keyHandled = $true
                        Invoke-XdrLiveSelectedQueryExecution -SelectedQuery $selectedQuery -QueryExecutionJob ([ref]$queryExecutionJob) -ModulePath $modulePath -Context $context -LogPath $dashboardLogPath
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
                            if ($selectedIncidentDetailsTab -eq 'entities' -and $selectedIncident) { Start-XdrLiveEntityExtraction -Incident $selectedIncident -EntityLoadJobsByIncidentId $entityLoadJobsByIncidentId -AlertsByIncidentId $alertsByIncidentId -ModulePath $modulePath -DashboardLogPath $dashboardLogPath }
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
                        Reset-XdrLiveDashboardDataForRefresh -Context $context -ReasonMessage 'Refreshing incidents and alert cache...' -PreserveSelection $true -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -SelectedEntity $selectedEntity -PendingRefreshIncidentId ([ref]$pendingRefreshIncidentId) -PendingRefreshAlertId ([ref]$pendingRefreshAlertId) -PendingRefreshEntityKey ([ref]$pendingRefreshEntityKey) -DataLoaded ([ref]$dataLoaded) -IncidentLoadJob ([ref]$incidentLoadJob) -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -EntityLoadJobsByIncidentId $entityLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -SelectedIndex ([ref]$selectedIndex) -SelectedAlertIndex ([ref]$selectedAlertIndex) -SelectedEntityIndex ([ref]$selectedEntityIndex) -SelectedIncidentRef ([ref]$selectedIncident) -SelectedAlertRef ([ref]$selectedAlert) -SelectedEntityRef ([ref]$selectedEntity) -AlertsByIncidentId $alertsByIncidentId -EntitiesByIncidentId $entitiesByIncidentId -EntityAlertCountByIncidentId $entityAlertCountByIncidentId -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -LogPath $dashboardLogPath
                        continue
                    }

                    if ($keyHandled) {
                        # Modal workflows consume the current keypress so it cannot also trigger
                        # normal panel actions later in the same loop iteration.
                    }

                    elseif (-not $selectedIncident -and -not $isQueryMode) {
                        continue
                    }

                    elseif ($isQueryMode -and $key.Key -eq 'DownArrow' -and $context.Data.QueryCatalog.Count -gt 0 -and $activePanel -ne 'query_actions') {
                        $keyHandled = $true
                        $activePanel = 'query_catalog'
                        $activePanelIndex = [array]::IndexOf($panelOrder, 'query_catalog')
                        $context.Selection.Panel = $activePanel
                        $selectedQueryIndex = ($selectedQueryIndex + 1) % $context.Data.QueryCatalog.Count
                        Sync-XdrSelectedQuery -Context $context -SelectedQueryIndex ([ref]$selectedQueryIndex) -SelectedQuery ([ref]$selectedQuery) -SelectedQueryResult ([ref]$selectedQueryResult) -QueryResultsByCacheKey $queryResultsByCacheKey
                        Set-LiveStatusMessage -Context $context -Message "Selected hunting query: $([string]$selectedQuery.name)" -Level 'info'
                    }
                    elseif ($isQueryMode -and $key.Key -eq 'UpArrow' -and $context.Data.QueryCatalog.Count -gt 0 -and $activePanel -ne 'query_actions') {
                        $keyHandled = $true
                        $activePanel = 'query_catalog'
                        $activePanelIndex = [array]::IndexOf($panelOrder, 'query_catalog')
                        $context.Selection.Panel = $activePanel
                        $selectedQueryIndex = ($selectedQueryIndex - 1 + $context.Data.QueryCatalog.Count) % $context.Data.QueryCatalog.Count
                        Sync-XdrSelectedQuery -Context $context -SelectedQueryIndex ([ref]$selectedQueryIndex) -SelectedQuery ([ref]$selectedQuery) -SelectedQueryResult ([ref]$selectedQueryResult) -QueryResultsByCacheKey $queryResultsByCacheKey
                        Set-LiveStatusMessage -Context $context -Message "Selected hunting query: $([string]$selectedQuery.name)" -Level 'info'
                    }
                    elseif ($isQueryMode -and $key.Key -eq 'Enter' -and $activePanel -eq 'query_catalog') {
                        $keyHandled = $true
                        Invoke-XdrLiveSelectedQueryExecution -SelectedQuery $selectedQuery -QueryExecutionJob ([ref]$queryExecutionJob) -ModulePath $modulePath -Context $context -LogPath $dashboardLogPath
                    }

                    elseif ($key.Key -eq 'DownArrow' -and $activePanel -eq 'incident_list') {
                        $selectedIndex = ($selectedIndex + 1) % $context.Data.Incidents.Count
                        $selectedIncident = $context.Data.Incidents[$selectedIndex]
                        $context.Selection.Incident = $selectedIncident
                        $selectedEntityIndex = 0
                        $selectedEntity = $null
                        $context.Selection.Entity = $null
                        $incidentId = [string]$selectedIncident.IncidentId
                        if (-not (Restore-XdrLiveCachedAlertsForIncident -IncidentId $incidentId -AlertsByIncidentId $alertsByIncidentId -Context $context -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex) -LogPath $dashboardLogPath)) {
                            $selectedAlert = $null
                            $selectedAlertIndex = 0
                            $context.Selection.Alert = $null
                            $context.Data.Alerts = @()
                            Clear-XdrLiveVisibleAlerts -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId)
                            Set-LiveStatusMessage -Context $context -Message 'Press Enter to load alerts for the selected incident.' -Level 'info'
                        }
                        else {
                            Sync-XdrLiveVisibleAlertsFromContext -Context $context -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -Incident $selectedIncident
                        }

                        if ($entitiesByIncidentId.ContainsKey($incidentId)) {
                            $context.Data.Entities = @($entitiesByIncidentId[$incidentId])
                        }
                        else {
                            $context.Data.Entities = @()
                        }
                        if ($selectedIncidentDetailsTab -eq 'entities' -and $selectedIncident) { Start-XdrLiveEntityExtraction -Incident $selectedIncident -EntityLoadJobsByIncidentId $entityLoadJobsByIncidentId -AlertsByIncidentId $alertsByIncidentId -ModulePath $modulePath -DashboardLogPath $dashboardLogPath }
                    }
                    elseif ($key.Key -eq 'UpArrow' -and $activePanel -eq 'incident_list') {
                        $selectedIndex = ($selectedIndex - 1 + $context.Data.Incidents.Count) % $context.Data.Incidents.Count
                        $selectedIncident = $context.Data.Incidents[$selectedIndex]
                        $context.Selection.Incident = $selectedIncident
                        $selectedEntityIndex = 0
                        $selectedEntity = $null
                        $context.Selection.Entity = $null
                        $incidentId = [string]$selectedIncident.IncidentId
                        if (-not (Restore-XdrLiveCachedAlertsForIncident -IncidentId $incidentId -AlertsByIncidentId $alertsByIncidentId -Context $context -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex) -LogPath $dashboardLogPath)) {
                            $selectedAlert = $null
                            $selectedAlertIndex = 0
                            $context.Selection.Alert = $null
                            $context.Data.Alerts = @()
                            Clear-XdrLiveVisibleAlerts -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId)
                            Set-LiveStatusMessage -Context $context -Message 'Press Enter to load alerts for the selected incident.' -Level 'info'
                        }
                        else {
                            Sync-XdrLiveVisibleAlertsFromContext -Context $context -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -Incident $selectedIncident
                        }

                        if ($entitiesByIncidentId.ContainsKey($incidentId)) {
                            $context.Data.Entities = @($entitiesByIncidentId[$incidentId])
                        }
                        else {
                            $context.Data.Entities = @()
                        }
                        if ($selectedIncidentDetailsTab -eq 'entities' -and $selectedIncident) { Start-XdrLiveEntityExtraction -Incident $selectedIncident -EntityLoadJobsByIncidentId $entityLoadJobsByIncidentId -AlertsByIncidentId $alertsByIncidentId -ModulePath $modulePath -DashboardLogPath $dashboardLogPath }
                    }
                    elseif ($key.Key -eq 'DownArrow' -and $activePanel -eq 'alert_list' -and $visibleAlerts.Count -gt 0) {
                        $selectedAlertIndex = ($selectedAlertIndex + 1) % $visibleAlerts.Count
                        $selectedAlert = $visibleAlerts[$selectedAlertIndex]
                        $context.Selection.Alert = $selectedAlert
                        $selectedAlertIdByIncidentId[[string]$selectedIncident.IncidentId] = [string]$selectedAlert.AlertId
                    }
                    elseif ($key.Key -eq 'UpArrow' -and $activePanel -eq 'alert_list' -and $visibleAlerts.Count -gt 0) {
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
                        Set-XdrLiveActiveTab -TabName 'hunting' -TabOrder $tabOrder -PanelOrder ([ref]$panelOrder) -Context $context -ActiveTabIndex ([ref]$activeTabIndex) -ActiveTab ([ref]$activeTab) -IsQueryMode ([ref]$isQueryMode) -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -SelectedActionIndex ([ref]$selectedActionIndex) -SelectedQueryIndex ([ref]$selectedQueryIndex) -SelectedQuery ([ref]$selectedQuery) -SelectedQueryResult ([ref]$selectedQueryResult) -QueryResultsByCacheKey $queryResultsByCacheKey -HideActionPanel:(-not $actionStatusPanelVisible)

                        $selectedEntityTypeLabel = [string]$selectedEntity.EntityType
                        $selectedEntityLabel = [string]$selectedEntity.DisplayName
                        Set-LiveStatusMessage -Context $context -Message "Switched to Hunting tab for ${selectedEntityTypeLabel}: $selectedEntityLabel" -Level 'info'
                    }
                    elseif ($key.Key -eq 'DownArrow' -and $activePanel -in @('incident_actions', 'query_actions') -and $actionEntries.Count -gt 0) {
                        $selectedActionIndex = ($selectedActionIndex + 1) % $actionEntries.Count
                    }
                    elseif ($key.Key -eq 'UpArrow' -and $activePanel -in @('incident_actions', 'query_actions') -and $actionEntries.Count -gt 0) {
                        $selectedActionIndex = ($selectedActionIndex - 1 + $actionEntries.Count) % $actionEntries.Count
                    }
                    elseif ($key.Key -eq 'Enter' -and $activePanel -in @('incident_list', 'incident_details')) {
                        if ($selectedIncident) {
                            $incidentId = [string]$selectedIncident.IncidentId
                            if (-not (Restore-XdrLiveCachedAlertsForIncident -IncidentId $incidentId -AlertsByIncidentId $alertsByIncidentId -Context $context -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex) -LogPath $dashboardLogPath)) {
                                if (Start-XdrLiveAlertLoadJob -Incident $selectedIncident -RestoreSelectionOnCompletion -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId) {
                                    Set-LiveStatusMessage -Context $context -Message 'Loading alerts in background...' -Level 'info'
                                }
                            }
                            else {
                                Sync-XdrLiveVisibleAlertsFromContext -Context $context -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -Incident $selectedIncident
                            }
                        }
                        if ($visibleAlerts.Count -gt 0) {
                            $activePanel = 'alert_list'
                            $activePanelIndex = [array]::IndexOf($panelOrder, 'alert_list')
                            $context.Selection.Panel = $activePanel
                        }
                    }
                    elseif ($key.Key -eq 'Enter' -and $activePanel -in @('incident_actions', 'query_actions') -and $actionEntries.Count -gt 0) {
                        $selectedAction = $actionEntries[$selectedActionIndex]
                        if ($selectedAction.IsEnabled) {
                            if ($isQueryMode) {
                                if ($selectedAction.Shortcut -eq 'x') {
                                    Invoke-XdrLiveSelectedQueryExecution -SelectedQuery $selectedQuery -QueryExecutionJob ([ref]$queryExecutionJob) -ModulePath $modulePath -Context $context -LogPath $dashboardLogPath
                                }
                                elseif ($selectedAction.Shortcut -eq 'h') {
                                    Set-XdrLiveActiveTab -TabName 'incidents' -TabOrder $tabOrder -PanelOrder ([ref]$panelOrder) -Context $context -ActiveTabIndex ([ref]$activeTabIndex) -ActiveTab ([ref]$activeTab) -IsQueryMode ([ref]$isQueryMode) -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -SelectedActionIndex ([ref]$selectedActionIndex) -SelectedQueryIndex ([ref]$selectedQueryIndex) -SelectedQuery ([ref]$selectedQuery) -SelectedQueryResult ([ref]$selectedQueryResult) -QueryResultsByCacheKey $queryResultsByCacheKey -HideActionPanel:(-not $actionStatusPanelVisible)
                                    Set-LiveStatusMessage -Context $context -Message 'Returned to incident workflow.' -Level 'info'
                                }
                            }
                            else {
                                Invoke-XdrLiveActionShortcut -Shortcut $selectedAction.Shortcut -Context $context -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -TriageOptions $triageOptions -PanelOrder $panelOrder -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -ActivePanelBeforeResolution ([ref]$activePanelBeforeResolution) -PendingConfirmation ([ref]$pendingConfirmation) -PendingTextInput ([ref]$pendingTextInput) -PendingIncidentResolution ([ref]$pendingIncidentResolution) -ActivePanelBeforeClassification ([ref]$activePanelBeforeClassification) -PendingIncidentClassification ([ref]$pendingIncidentClassification) -ActivePanelBeforeComment ([ref]$activePanelBeforeComment) -PendingIncidentComment ([ref]$pendingIncidentComment) -ModulePath $modulePath -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlertIndex ([ref]$selectedAlertIndex) -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -LogPath $dashboardLogPath
                            }
                        }
                        else {
                            Set-LiveStatusMessage -Context $context -Message "$($selectedAction.Label) is not available right now." -Level 'warning'
                        }
                    }
                    elseif ($isAltPressed -and $isShiftPressed -and $key.Key -eq 'L') {
                        Invoke-XdrLiveActionShortcut -Shortcut 'reload-alerts' -Context $context -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -TriageOptions $triageOptions -PanelOrder $panelOrder -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -ActivePanelBeforeResolution ([ref]$activePanelBeforeResolution) -PendingConfirmation ([ref]$pendingConfirmation) -PendingTextInput ([ref]$pendingTextInput) -PendingIncidentResolution ([ref]$pendingIncidentResolution) -ActivePanelBeforeClassification ([ref]$activePanelBeforeClassification) -PendingIncidentClassification ([ref]$pendingIncidentClassification) -ActivePanelBeforeComment ([ref]$activePanelBeforeComment) -PendingIncidentComment ([ref]$pendingIncidentComment) -ModulePath $modulePath -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlertIndex ([ref]$selectedAlertIndex) -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -LogPath $dashboardLogPath
                    }
                    elseif ($isAltPressed -and $keyChar -in @('a', 'u', 'o', 'i', 'r', 'k', 'c', 'l', 'n', 'p', 'm')) {
                        Invoke-XdrLiveActionShortcut -Shortcut $keyChar -Context $context -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -TriageOptions $triageOptions -PanelOrder $panelOrder -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -ActivePanelBeforeResolution ([ref]$activePanelBeforeResolution) -PendingConfirmation ([ref]$pendingConfirmation) -PendingTextInput ([ref]$pendingTextInput) -PendingIncidentResolution ([ref]$pendingIncidentResolution) -ActivePanelBeforeClassification ([ref]$activePanelBeforeClassification) -PendingIncidentClassification ([ref]$pendingIncidentClassification) -ActivePanelBeforeComment ([ref]$activePanelBeforeComment) -PendingIncidentComment ([ref]$pendingIncidentComment) -ModulePath $modulePath -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlertIndex ([ref]$selectedAlertIndex) -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -LogPath $dashboardLogPath
                    }

                }
                finally {
                    Set-XdrLastInputDiagnostics -Context $context -Key $key -InputTime $currentInputTime -KeyCharDisplay $keyCharDisplay -ModifierSummary $modifierSummary -KeyHandled $keyHandled -ActivePanel $activePanel -IsQueryMode $isQueryMode -SelectedQueryIndex $selectedQueryIndex -SelectedQuery $selectedQuery -SelectedEntity $selectedEntity
                }
            }  # end foreach ($key in @($keysForMainHandler))

            # If there are no incidents, ensure selection is cleared and panels show appropriate messaging instead of stale data from previous incidents
            if (-not $context.Data.Incidents -and $activeTab -ne 'hunting') {
                $selectedEntity = $null
                $context.Selection.Entity = $null
                Update-XdrLiveOuterTabs -DashboardFrame $dashboardFrame -ScreenLayout $screenLayout -TabOrder $tabOrder -ActiveTabIndex $activeTabIndex
                if ($activeTab -eq 'incidents') {
                    $layout['left_top'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_list' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No incidents found. Press Ctrl+C to exit.' -Expand)) | Out-Null
                    $emptyIncidentDetailsData = if ($selectedIncidentDetailsTab -eq 'entities') { 'No incident selected. Press Alt+E for entities view.' } else { 'No incident selected.' }
                    $layout['center_top'].Update((Format-SpectrePanel -Header $incidentDetailsHeader -Data $emptyIncidentDetailsData -Expand)) | Out-Null
                    $layout['left_bottom'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_list' -Title 'Alert List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No incident selected.' -Expand)) | Out-Null
                    $layout['center_bottom'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No alert selected.' -Expand)) | Out-Null
                    if ($actionStatusPanelVisible) { $layout['right_actions'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_actions' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No incident selected.' -Expand)) | Out-Null }
                }
                $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -SelectedIncident $selectedIncident -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -LastRefreshAt $lastDataRefreshAt -HeartbeatAt $lastHeartbeat -HeartbeatCounter $heartbeatCounter) -Expand)) | Out-Null
                if ($activeTab -ne 'incidents') {
                    Show-XdrLiveNonIncidentTab -Layout $layout -ActiveTab $activeTab -ActivePanel $activePanel -Context $context -DashboardLogPath $dashboardLogPath -TenantId $TenantId -ClientId $ClientId -SelectedIncident $selectedIncident -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -LastRefreshAt $lastDataRefreshAt -HeartbeatAt $lastHeartbeat -HeartbeatCounter $heartbeatCounter -IsQueryMode $isQueryMode -ShowKeyboardHelpOverlay $showKeyboardHelpOverlay -ActionPanelVisible $actionStatusPanelVisible
                }
                $LiveContext.Refresh()
                Start-Sleep -Milliseconds $context.Ui.RefreshIntervalMs
                continue
            }

            #region Build renderables from settled state
            # From here to the final Refresh(), build renderables from the settled state
            # rather than mutating Graph/job data. Spectre layout updates happen only after
            # every panel has been prepared.
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

                    # the use of regex here allows for some flexibility in status text while still mapping to the right colors, e.g. "In Progress" vs "InProgress"
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
            #endregion Build renderables from settled state

            $incidentPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_list' -Title "Incident List ($($context.Data.Incidents.Count))" -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data (($incidentLines | Out-String)) -Color (Get-PanelBorderColor -PanelName 'incident_list' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'incident_list' -ActivePanel $activePanel) -Expand

            $incidentDetails = if ($selectedIncidentDetailsTab -eq 'entities') {
                # Entities come from the extractor cache when available, with lightweight
                # fallback rows so the panel still gives analysts useful context early.
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
                            EntityType  = 'User'
                            DisplayName = [string]$selectedIncident.AssignedTo
                            IncidentId  = [string]$selectedIncident.IncidentId
                            AlertId     = $null
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
                            EntityType  = 'Alert'
                            DisplayName = $alertEntityLabel
                            IncidentId  = [string]$selectedIncident.IncidentId
                            AlertId     = [string]$alertRow.AlertId
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
            } else {
                [pscustomobject]@{
                    IncidentId     = $selectedIncident.IncidentId
                    DisplayName    = $selectedIncident.DisplayName
                    Status         = $selectedIncident.Status
                    Classification = $selectedIncident.Classification
                    Determination  = $selectedIncident.Determination
                    AssignedTo     = $selectedIncident.AssignedTo
                    Severity       = $selectedIncident.Severity
                    AlertCount     = $selectedIncident.AlertCount
                    SystemTags     = @($selectedIncident.SystemTags)
                    CustomTags     = @($selectedIncident.CustomTags)
                    LastUpdated    = $selectedIncident.LastUpdateDateTime
                    IncidentWebUrl = $selectedIncident.IncidentWebUrl
                    Created        = $selectedIncident.CreatedDateTime
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
            } else {
                @('Press Enter on an incident to load alerts.')
            }

            $alertsPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_list' -Title "Alert List ($($visibleAlerts.Count))" -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data (($alertLines | Out-String)) -Color (Get-PanelBorderColor -PanelName 'alert_list' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'alert_list' -ActivePanel $activePanel) -Expand

            $alertDetails = if ($selectedAlert) {
                [pscustomobject]@{
                    AlertId     = $selectedAlert.AlertId
                    Title       = $selectedAlert.Title
                    Status      = $selectedAlert.Status
                    Severity    = $selectedAlert.Severity
                    Created     = $selectedAlert.CreatedDateTime
                    AlertWebUrl = $selectedAlert.AlertWebUrl
                } | Format-SpectreJson | Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Color (Get-PanelBorderColor -PanelName 'alert_details' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'alert_details' -ActivePanel $activePanel) -Expand
            } else {
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

            # Action entries back both the rendered action panel and Enter-key execution,
            # so disabled reasons and shortcuts stay in one list.
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
                        Shortcut  = $shortcutKey
                        Label     = "Set alert status to $statusLabel"
                        IsEnabled = $false
                        Reasons   = $reasons
                    }
                }
            }

            if ($actionEntries.Count -eq 0) {
                $selectedActionIndex = 0
            }
            else {
                $selectedActionIndex = [Math]::Min($selectedActionIndex, $actionEntries.Count - 1)
            }

            # Render action rows with a cursor independent of blank/header lines so the
            # selected action index maps to actionable entries only.
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
                        $isSelected = ($activePanel -eq 'incident_actions' -and $actionCursor -eq $selectedActionIndex)
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

            # Modal renderers replace the normal action list with the active wizard while
            # the input handler above keeps focus pinned to the action panel.
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

                $actionStatusPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_actions' -Title 'Incident Resolution Wizard' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($resolutionLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'incident_actions' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'incident_actions' -ActivePanel $activePanel) -Expand
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

                $actionStatusPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_actions' -Title 'Incident Classification Wizard' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($classificationLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'incident_actions' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'incident_actions' -ActivePanel $activePanel) -Expand
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

                $actionStatusPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_actions' -Title 'Incident Comment Wizard' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($commentLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'incident_actions' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'incident_actions' -ActivePanel $activePanel) -Expand
            }
            else {
                $actionStatusPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_actions' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($actionDisplayLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'incident_actions' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'incident_actions' -ActivePanel $activePanel) -Expand
            }

            # Hunting reuses the same physical panels but swaps their meaning to query
            # catalog, preview, activity, results, and query actions.
            $isQueryMode = ($activeTab -eq 'hunting')
            if ($activeTab -eq 'hunting') {
                Sync-XdrSelectedQuery -Context $context -SelectedQueryIndex ([ref]$selectedQueryIndex) -SelectedQuery ([ref]$selectedQuery) -SelectedQueryResult ([ref]$selectedQueryResult) -QueryResultsByCacheKey $queryResultsByCacheKey

                $queryCatalogLines = @()
                $queryRunHistory = @($context.Data.QueryRuns | Sort-Object -Property ExecutedAt -Descending)
                $selectedQueryResolution = $null
                $selectedQueryPreview = $null
                $selectedQueryPreviewError = $null

                # Resolve required query context before preview/execution so blocked
                # queries can explain exactly which incident/entity value is missing.
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
                        $queryPrefix = if ($isSelectedQuery -and $activePanel -eq 'query_catalog') { "[bold $($context.Ui.ThemeColor)]>[/]" } else { ' ' }
                        $queryNameMarkup = if ($isSelectedQuery) { "[bold $($context.Ui.ThemeColor)]$([string](Get-SpectreEscapedText ([string]$queryDefinition.name)))[/]" } else { "[white]$([string](Get-SpectreEscapedText ([string]$queryDefinition.name)))[/]" }
                        $queryStatusMarkup = if ($queryResolution.IsBlocked) { '[bold red]BLOCKED[/]' } else { '[bold green]READY[/]' }
                        $queryCatalogLines += "$queryPrefix $queryNameMarkup $queryStatusMarkup"
                        $queryCatalogLines += "  [grey]$([string](Get-SpectreEscapedText ([string]$queryDefinition.description)))[/]"

                        if ($queryResolution.IsBlocked) {
                            $queryCatalogLines += "  [darkred]Missing: $([string](Get-SpectreEscapedText (($queryResolution.MissingContext -join ', '))))[/]"
                            $queryCatalogLines += "  [grey]Hint: $([string](Get-SpectreEscapedText ([string](Get-XdrQueryContextGuidance -ContextKey $queryResolution.MissingContext[0]))))[/]"
                        }
                        elseif (@($queryDefinition.tags).Count -gt 0) {
                            $queryCatalogLines += "  [grey]Tags: $([string](Get-SpectreEscapedText ((@($queryDefinition.tags) -join ', '))))[/]"
                        }

                        $queryCatalogLines += ''
                    }
                }

                $incidentPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'query_catalog' -Title "Query Catalog ($(@($context.Data.QueryCatalog).Count))" -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($queryCatalogLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'query_catalog' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'query_catalog' -ActivePanel $activePanel) -Expand

                if (-not $selectedQuery) {
                    $incidentDetails = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'query_preview' -Title 'Query Preview' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No hunting query selected.' -Color (Get-PanelBorderColor -PanelName 'query_preview' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'query_preview' -ActivePanel $activePanel) -Expand
                }
                elseif ($selectedQueryResolution.IsBlocked) {
                    $blockedPreviewLines = @(
                        "[bold]$([string](Get-SpectreEscapedText ([string]$selectedQuery.name)))[/]",
                        "[grey]$([string](Get-SpectreEscapedText ([string]$selectedQuery.description)))[/]",
                        '',
                        "[darkred]Missing required context: $([string](Get-SpectreEscapedText (($selectedQueryResolution.MissingContext -join ', '))))[/]",
                        "[grey]Hint: $([string](Get-SpectreEscapedText ([string](Get-XdrQueryContextGuidance -ContextKey $selectedQueryResolution.MissingContext[0]))))[/]"
                    )
                    $incidentDetails = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'query_preview' -Title 'Query Preview' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($blockedPreviewLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'query_preview' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'query_preview' -ActivePanel $activePanel) -Expand
                }
                elseif (-not [string]::IsNullOrWhiteSpace($selectedQueryPreviewError)) {
                    $incidentDetails = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'query_preview' -Title 'Query Preview' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data $selectedQueryPreviewError -Color (Get-PanelBorderColor -PanelName 'query_preview' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'query_preview' -ActivePanel $activePanel) -Expand
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
                    $incidentDetails = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'query_preview' -Title 'Query Preview' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($previewLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'query_preview' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'query_preview' -ActivePanel $activePanel) -Expand
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

                $alertsPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'query_activity' -Title "Activity Log ($($queryRunHistory.Count))" -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($activityLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'query_activity' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'query_activity' -ActivePanel $activePanel) -Expand

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

                $alertDetails = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'query_results' -Title 'Query Results' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($resultLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'query_results' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'query_results' -ActivePanel $activePanel) -Expand

                # Query execution is disabled while a job is running or required context
                # is missing; the same reasons are rendered in the action panel.
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
                    $queryActionLines += "Hint: $([string](Get-XdrQueryContextGuidance -ContextKey $selectedQueryResolution.MissingContext[0]))"
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
                            $isSelected = ($activePanel -eq 'query_actions' -and $queryActionCursor -eq $selectedActionIndex)
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

                $actionStatusPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'query_actions' -Title 'Query Actions' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($queryActionDisplayLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'query_actions' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'query_actions' -ActivePanel $activePanel) -Expand
            }

            # Help is rebuilt last so it can reflect any key handling, job completion, or
            # mode switch that happened earlier in this loop iteration.
            $contextHelpLine = (Get-ContextAwareHelpLines -ActivePanel $activePanel -IsQueryMode:$isQueryMode -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation -PendingTextInput $pendingTextInput -PendingIncidentResolution $pendingIncidentResolution -PendingIncidentClassification $pendingIncidentClassification -PendingIncidentComment $pendingIncidentComment) -join ' | '
            $helpHeaderText = if ($showKeyboardHelpOverlay) { 'Help (F1 close)' } else { "Help | $contextHelpLine" }
            $helpPanel = Format-SpectrePanel -Header "[white]$helpHeaderText[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -SelectedIncident $selectedIncident -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -LastRefreshAt $lastDataRefreshAt -HeartbeatAt $lastHeartbeat -HeartbeatCounter $heartbeatCounter -IsQueryMode:$isQueryMode -ShowKeyboardHelpOverlay:$showKeyboardHelpOverlay) -Color (Get-PanelBorderColor -PanelName 'help' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'help' -ActivePanel $activePanel) -Expand

            Update-XdrLiveOuterTabs -DashboardFrame $dashboardFrame -ScreenLayout $screenLayout -TabOrder $tabOrder -ActiveTabIndex $activeTabIndex

            # Only incidents and hunting own the full dynamic panel set. Other tabs render
            # through a shared placeholder helper while background jobs keep running.
            if ($activeTab -in @('incidents', 'hunting')) {
                $layout['left_top'].Update($incidentPanel) | Out-Null
                $layout['center_top'].Update($incidentDetails) | Out-Null
                $layout['left_bottom'].Update($alertsPanel) | Out-Null
                $layout['center_bottom'].Update($alertDetails) | Out-Null
                if ($actionStatusPanelVisible) { $layout['right_actions'].Update($actionStatusPanel) | Out-Null }
                $layout['help'].Update($helpPanel) | Out-Null
            }
            else {
                Show-XdrLiveNonIncidentTab -Layout $layout -ActiveTab $activeTab -ActivePanel $activePanel -Context $context -CurrentHelpPanel $helpPanel -DashboardLogPath $dashboardLogPath -TenantId $TenantId -ClientId $ClientId -SelectedIncident $selectedIncident -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -LastRefreshAt $lastDataRefreshAt -HeartbeatAt $lastHeartbeat -HeartbeatCounter $heartbeatCounter -IsQueryMode $isQueryMode -ShowKeyboardHelpOverlay $showKeyboardHelpOverlay -ActionPanelVisible $actionStatusPanelVisible
            }
            $LiveContext.Refresh()

            Start-Sleep -Milliseconds $context.Ui.RefreshIntervalMs
        }
    }
}
