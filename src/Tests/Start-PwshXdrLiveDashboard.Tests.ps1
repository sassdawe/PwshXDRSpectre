BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
    $script:dashboardPath = Join-Path $PSScriptRoot '..' 'Public' 'Start-PwshXdrLiveDashboard.ps1'
    $script:privateRoot = Join-Path $PSScriptRoot '..' 'Private'
}

Describe 'Start-PwshXdrLiveDashboard wiring' {
    It 'does not call Graph mutation cmdlets directly' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content | Should -Not -Match 'Update-MgSecurityIncident'
        $content | Should -Not -Match 'Update-MgSecurityAlertV2'
        $content | Should -Not -Match 'Invoke-MgGraphRequest\s*-Method\s*(POST|PATCH|PUT|DELETE)'
    }

    It 'recomputes disabled reasons for incident and alert actions in render flow' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("Get-XdrActionDisableReasons -ActionName 'Assign incident to me' -ActionType Incident -Context `$context") | Should -BeTrue
        $content.Contains("Get-XdrActionDisableReasons -ActionName 'Clear incident assignment' -ActionType Incident -Context `$context") | Should -BeTrue
        $content.Contains('Get-XdrActionDisableReasons -ActionName "Set incident status to $statusLabel" -ActionType Incident -Context $context -CurrentStatus $selectedIncident.Status -RequestedStatus $requestedStatus') | Should -BeTrue
        $content.Contains('Get-XdrActionDisableReasons -ActionName "Set alert status to $statusLabel" -ActionType Alert -Context $context -CurrentStatus $selectedAlert.Status -RequestedStatus $requestedStatus') | Should -BeTrue
        $content.Contains("`$reasons = @('Unavailable')") | Should -BeTrue
    }

    It 'does not expose PanelFocus in incident or alert detail JSON payloads' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content | Should -Not -Match 'PanelFocus\s*='
    }

    It 'includes incident tags and classification metadata in the incident details payload' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('Classification = $selectedIncident.Classification') | Should -BeTrue
        $content | Should -Match 'SystemTags\s*=\s*@\(\$selectedIncident\.SystemTags\)'
        $content | Should -Match 'CustomTags\s*=\s*@\(\$selectedIncident\.CustomTags\)'
        $content | Should -Match 'LastUpdated\s*=\s*\$selectedIncident\.LastUpdateDateTime'
        $content | Should -Not -Match 'RedirectIncidentId\s*='
    }

    It 'renders incident list entries with severity badge and incident id' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('$incidentIdWidth = 2') | Should -BeTrue
        $content.Contains('$incidentStatusWidth = 6') | Should -BeTrue
        $content.Contains('$incidentTitleWidth = [Math]::Max(8, $incidentListPanelWidth - $incidentSeverityWidth - $incidentIdWidth - $incidentStatusWidth - 3)') | Should -BeTrue
        $content.Contains('$severityColor = switch ($severityKey) {') | Should -BeTrue
        $content.Contains('$statusColor = switch -Regex ($statusKey) {') | Should -BeTrue
        $content.Contains('$idColumn = if ([string]::IsNullOrWhiteSpace($incidentIdText)) { ''--'' } else { $incidentIdText }') | Should -BeTrue
        $content.Contains('$titleColumn = $displayNameText') | Should -BeTrue
        $content.Contains('$titleColumn = $titleColumn.Substring(0, $incidentTitleWidth - 3) + ''...''') | Should -BeTrue
        $layoutContent = Get-Content -Path (Join-Path $script:privateRoot 'New-XdrLiveDashboardLayout.ps1') -Raw
        $layoutContent.Contains("(New-SpectreLayout -Name 'left_bottom' -Ratio 1 -Data 'empty')") | Should -BeTrue
        $content | Should -Match 'Ⓗ|Ⓜ|Ⓛ|Ⓤ'
    }

    It 'uses nested layout structure with toggleable right actions column' {
        $content = Get-Content -Path $script:dashboardPath -Raw
        $layoutContent = Get-Content -Path (Join-Path $script:privateRoot 'New-XdrLiveDashboardLayout.ps1') -Raw
        $outerTabsContent = Get-Content -Path (Join-Path $script:privateRoot 'Update-XdrLiveOuterTabs.ps1') -Raw
        $outerTabsHeaderContent = Get-Content -Path (Join-Path $script:privateRoot 'Get-XdrLiveOuterTabsHeader.ps1') -Raw

        $content.Contains('$layout = New-XdrLiveDashboardLayout -ActionPanelVisible') | Should -BeTrue
        $layoutContent.Contains("New-SpectreLayout -Name 'main_content' -Ratio 10 -Columns `$mainColumns") | Should -BeTrue
        $layoutContent.Contains("New-SpectreLayout -Name 'left_lists' -Ratio `$leftRatio -Rows") | Should -BeTrue
        $layoutContent.Contains("New-SpectreLayout -Name 'center_details' -Ratio `$centerRatio -Rows") | Should -BeTrue
        $content.Contains("`$dashboardFrame = Format-SpectrePanel -Data `$layout -Header ' ' -Color 'deepskyblue1' -Border 'Rounded' -Expand") | Should -BeTrue
        $content.Contains("New-SpectreLayout -Name 'dashboard_frame' -Ratio 1 -Data `$dashboardFrame") | Should -BeTrue
        $content.Contains('Update-XdrLiveOuterTabs -DashboardFrame $dashboardFrame -ScreenLayout $screenLayout') | Should -BeTrue
        $outerTabsContent.Contains('$DashboardFrame.Header = [Spectre.Console.PanelHeader]::new($outerTabsHeader, [Spectre.Console.Justify]::Left)') | Should -BeTrue
        $outerTabsContent.Contains("`$ScreenLayout['dashboard_frame'].Update(`$DashboardFrame) | Out-Null") | Should -BeTrue
        $outerTabsHeaderContent | Should -Match '\[bold black on orange1\]\| \$label \|\[/\]'
        $outerTabsHeaderContent | Should -Match '\[deepskyblue1 on #1C1C1C\]\| \$label \|\[/\]'
        $content.Contains('Invoke-SpectreLive -Data $screenLayout -ScriptBlock') | Should -BeTrue
        $layoutContent.Contains("(New-SpectreLayout -Name 'left_top' -Ratio 1 -Data 'empty')") | Should -BeTrue
        $layoutContent.Contains("(New-SpectreLayout -Name 'left_bottom' -Ratio 1 -Data 'empty')") | Should -BeTrue
        $layoutContent.Contains("(New-SpectreLayout -Name 'center_top' -Ratio 1 -Data 'empty')") | Should -BeTrue
        $layoutContent.Contains("(New-SpectreLayout -Name 'center_bottom' -Ratio 1 -Data 'empty')") | Should -BeTrue
        $layoutContent.Contains("New-SpectreLayout -Name 'right_actions' -Ratio 2 -Data 'empty'") | Should -BeTrue
        $layoutContent.Contains('$leftRatio = if ($ActionPanelVisible.IsPresent) { 2 } else { 1 }') | Should -BeTrue
        $layoutContent.Contains('$centerRatio = if ($ActionPanelVisible.IsPresent) { 3 } else { 1 }') | Should -BeTrue
        $content | Should -Not -Match "New-SpectreLayout -Name 'outer_tabs'"
        $content | Should -Not -Match "\['outer_tabs'\]"
        $content | Should -Not -Match "New-SpectreLayout -Name 'header'"
        $content | Should -Not -Match "\['header'\]"
        $content | Should -Not -Match 'Get-XdrLiveHeaderPanel -Context \$context'
        $content | Should -Not -Match "Format-SpectrePanel -Header '\[white\]Global navigation"
    }

    It 'renders alert list entries with severity badge incident-style columns and status' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('$alertStatusWidth = 6') | Should -BeTrue
        $content.Contains('$alertTitleWidth = [Math]::Max(8, $incidentListPanelWidth - $alertSeverityWidth - $alertStatusWidth - 2)') | Should -BeTrue
        $content.Contains('$titleText = [string]$_.Title') | Should -BeTrue
        $content.Contains('$statusText = [string]$_.Status') | Should -BeTrue
        $content.Contains('$severityText = [string]$_.Severity') | Should -BeTrue
        $content.Contains('$titleColumn = $titleColumn.Substring(0, $alertTitleWidth - 3) + ''...''') | Should -BeTrue
        $content | Should -Not -Match '\$alertIdText\s*='
    }

    It 'keeps incident resolve mutation inside the final confirm step branch' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("`$currentResolutionStep = [string]`$pendingIncidentResolution.Step") | Should -BeTrue
        $content.Contains('switch ($currentResolutionStep) {') | Should -BeTrue
        $content.Contains("'confirm' {") | Should -BeTrue
        $content.Contains("elseif ((-not `$isAltPressed -and -not `$isCtrlPressed -and `$keyChar -eq 'y') -or `$key.Key -eq 'Enter') {") | Should -BeTrue
        $content.Contains("`$resolveResult = Set-XdrIncidentTriage -Context `$context -IncidentId `$selectedIncident.IncidentId -Status 'Resolved' -Classification `$selectedClassificationLabel -Determination `$selectedDeterminationLabel -Comment `$commentText -SkipConfirmation") | Should -BeTrue
    }

    It 'consumes modal keypresses before normal action-panel Enter handling' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('$keyHandled = $false') | Should -BeTrue
        $content.Contains('if ($null -ne $pendingIncidentResolution) {') | Should -BeTrue
        $content.Contains('$keyHandled = $true') | Should -BeTrue
        $content.Contains('if ($keyHandled) {') | Should -BeTrue
        $content.Contains("elseif (`$key.Key -eq 'Enter' -and `$activePanel -in @('incident_actions', 'query_actions') -and `$actionEntries.Count -gt 0) {") | Should -BeTrue
    }

    It 'renders incident resolution as a per-step wizard page' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("switch (`$stepName) {") | Should -BeTrue
        $content.Contains("'classification' {") | Should -BeTrue
        $content.Contains("'determination' {") | Should -BeTrue
        $content.Contains("'comment' {") | Should -BeTrue
        $content.Contains("default {") | Should -BeTrue
        $content.Contains("-Title 'Incident Resolution Wizard'") | Should -BeTrue
    }

    It 'uses buffered key capture for text-entry wizard steps and hunting mode' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("`$isQueryMode -or") | Should -BeTrue
        $content.Contains("`$null -ne `$pendingTextInput -or") | Should -BeTrue
        $content.Contains("(`$null -ne `$pendingIncidentComment -and [string]`$pendingIncidentComment.Step -eq 'comment') -or") | Should -BeTrue
        $content.Contains("(`$null -ne `$pendingIncidentResolution -and [string]`$pendingIncidentResolution.Step -eq 'comment')") | Should -BeTrue
        $content.Contains('@(Get-XdrAllKeysPressed)') | Should -BeTrue
    }

    It 'supports toggling between incident details and related entities panel' {
        $content = Get-Content -Path $script:dashboardPath -Raw
        $headerContent = Get-Content -Path (Join-Path $script:privateRoot 'Get-XdrIncidentDetailsTabHeader.ps1') -Raw

        $content.Contains("elseif (`$isAltPressed -and `$keyChar -eq 'e')") | Should -BeTrue
        $content.Contains("elseif (`$isAltPressed -and `$keyChar -eq 'd')") | Should -BeTrue
        $content.Contains("`$activePanel = 'incident_details'") | Should -BeTrue
        $content.Contains("`$panelOrder = @(Get-XdrLivePanelOrder -TabName `$activeTab -HideActionPanel:(-not `$actionStatusPanelVisible))") | Should -BeTrue
        $content.Contains("`$selectedIncidentDetailsTab = 'entities'") | Should -BeTrue
        $content.Contains("`$selectedIncidentDetailsTab = 'details'") | Should -BeTrue
        $content.Contains('Get-XdrIncidentDetailsTabHeader -CurrentTab $selectedIncidentDetailsTab') | Should -BeTrue
        $headerContent.Contains("[bold black on orange1]| Incident details |[/] [deepskyblue1 on #1C1C1C]| Entities |[/] [grey](ALT+E to switch)[/]") | Should -BeTrue
        $headerContent.Contains("[deepskyblue1 on #1C1C1C]| Incident details |[/] [bold black on orange1]| Entities |[/] [grey](ALT+D to switch)[/]") | Should -BeTrue
        $content.Contains("Tab to switch to Details") | Should -BeTrue
    }

    It 'extracts entities in background and renders entity-specific preview actions' {
        $content = Get-Content -Path $script:dashboardPath -Raw
        $entityExtractionContent = Get-Content -Path (Join-Path $script:privateRoot 'Start-XdrLiveEntityExtraction.ps1') -Raw

        $content.Contains('Start-XdrLiveEntityExtraction -Incident $selectedIncident') | Should -BeTrue
        $entityExtractionContent.Contains('Start-ThreadJob -ScriptBlock {') | Should -BeTrue
        $entityExtractionContent.Contains('$jobPayload = [pscustomobject]@{') | Should -BeTrue
        $entityExtractionContent.Contains('AlertData        = @($alertsForIncident)') | Should -BeTrue
        $entityExtractionContent.Contains('} -ArgumentList $jobPayload') | Should -BeTrue
        $entityExtractionContent.Contains('Write-XdrLiveDashboardLog -LogPath $InnerDashboardLogPath -Message "Entity extraction job started. IncidentId=$InnerIncidentId"') | Should -BeTrue
        $entityExtractionContent.Contains('} $JobPayload.DashboardLogPath $JobPayload.IncidentId') | Should -BeTrue
        $entityExtractionContent.Contains('& (Get-Module PwshXDRSpectre) {') | Should -BeTrue
        $entityExtractionContent.Contains('Get-XdrIncidentEntities -Incident $InnerIncidentData -Alerts $InnerAlertData') | Should -BeTrue
        $entityExtractionContent.Contains('} $JobPayload.IncidentData @($JobPayload.AlertData)') | Should -BeTrue
        $entityExtractionContent | Should -Not -Match '\}\s*\$JobPayload\.DashboardLogPath,\s*\$JobPayload\.IncidentId'
        $content.Contains("'Entity actions (preview)'") | Should -BeTrue
        $content.Contains('$distinctEntityAlertIds = @($entityEntries | Where-Object {') | Should -BeTrue
        $content.Contains('$shouldSeparateEntityAlertGroups = $distinctEntityAlertIds.Count -gt 1') | Should -BeTrue
        $content.Contains('$entityAlertId -ne $previousEntityAlertId') | Should -BeTrue
        $content.Contains("`$entityLines += ''") | Should -BeTrue
        $content.Contains("`$selectedEntityType = [string]`$selectedEntity.EntityType") | Should -BeTrue
        $content.Contains("'^(?i:user|account)$' { @('Revoke user sessions', 'Disable user account') }") | Should -BeTrue
        $content.Contains("'^(?i:device|machine)$' { @('Isolate device', 'Run antivirus scan', 'Collect investigation package') }") | Should -BeTrue
        $content.Contains("'^(?i:file)$' { @('Quarantine file', 'Block file indicator', 'Remove file indicator block') }") | Should -BeTrue
        $content.Contains("'[grey]No entity selected.[/]'") | Should -BeTrue
        $content.Contains("elseif (`$selectedIncidentDetailsTab -eq 'entities' -and `$key.Key -eq 'DownArrow' -and `$activePanel -eq 'incident_details' -and `$context.Data.Entities.Count -gt 0)") | Should -BeTrue
    }

    It 'supports entity panel up-arrow navigation and selection reset on incident change' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("elseif (`$selectedIncidentDetailsTab -eq 'entities' -and `$key.Key -eq 'UpArrow' -and `$activePanel -eq 'incident_details' -and `$context.Data.Entities.Count -gt 0)") | Should -BeTrue
        $content.Contains("`$selectedEntityIndex = 0") | Should -BeTrue
        $content.Contains("`$selectedEntity = `$null") | Should -BeTrue
        $content.Contains("`$context.Selection.Entity = `$null") | Should -BeTrue
    }

    It 'switches from selected entity into the Hunting tab on Enter and shows selected entity in query actions' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("elseif (`$selectedIncidentDetailsTab -eq 'entities' -and `$key.Key -eq 'Enter' -and `$activePanel -eq 'incident_details' -and `$selectedEntity)") | Should -BeTrue
        $content.Contains("Set-XdrLiveActiveTab -TabName 'hunting'") | Should -BeTrue
        $content.Contains("`$selectedQueryResult = `$null") | Should -BeTrue
        $content.Contains('Set-LiveStatusMessage -Context $context -Message "Switched to Hunting tab for ${selectedEntityTypeLabel}: $selectedEntityLabel" -Level ''info''') | Should -BeTrue
        $content.Contains('Selected entity: $([string]$selectedEntity.EntityType) | $([string]$selectedEntity.DisplayName)') | Should -BeTrue
    }

    It 'auto-refreshes incidents every three minutes and passes last refresh to help content' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('$autoRefreshInterval = [timespan]::FromMinutes(3)') | Should -BeTrue
        $content.Contains("Auto-refreshing incidents and alerts (every 3 minutes)...") | Should -BeTrue
        $content.Contains("Reset-XdrLiveDashboardDataForRefresh -Context `$context -ReasonMessage 'Auto-refreshing incidents and alerts (every 3 minutes)...'") | Should -BeTrue
        $content.Contains('-LastRefreshAt $lastDataRefreshAt') | Should -BeTrue
        $content.Contains('[switch]$WithLogs') | Should -BeTrue
        $content.Contains('[string]$LogPath') | Should -BeTrue
        $content.Contains('Dashboard log file: $dashboardLogPath') | Should -BeTrue
    }

    It 'builds a whitespace-free timestamped .log filename when logs are enabled without an explicit path' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("`$dashboardLogTimestamp = Get-Date -Format 'yyyyMMddTHHmmssfff'") | Should -BeTrue
        $content.Contains('$dashboardLogFileName = "live-dashboard-$dashboardLogTimestamp.log"') | Should -BeTrue
        $content.Contains('Join-Path $dashboardLogDirectory $dashboardLogFileName') | Should -BeTrue
        $content | Should -Not -Match 'live-dashboard-\{0\}\.log'
    }

    It 'supports keyboard help overlay, quick quit confirmation, and r refresh alias' {
        $content = Get-Content -Path $script:dashboardPath -Raw
        $nonIncidentTabContent = Get-Content -Path (Join-Path $script:privateRoot 'Show-XdrLiveNonIncidentTab.ps1') -Raw

        $content.Contains("`$pendingQuitConfirmation = `$false") | Should -BeTrue
        $content.Contains("`$showKeyboardHelpOverlay = `$false") | Should -BeTrue
        $content.Contains("elseif (`$key.Key -eq 'F1')") | Should -BeTrue
        $content.Contains("elseif (Test-XdrConsoleShortcut -Key `$key -KeyName 'k' -Alt -Control)") | Should -BeTrue
        $content.Contains("`$context.Diagnostics.InputDebugEnabled = -not `$context.Diagnostics.InputDebugEnabled") | Should -BeTrue
        $content.Contains("elseif (Test-XdrConsoleShortcut -Key `$earlyKey -KeyName 'k' -Alt -Control)") | Should -BeTrue
        $content.Contains("elseif (Test-XdrConsoleShortcut -Key `$earlyKey -KeyName 'a' -Alt -Control)") | Should -BeTrue
        $content.Contains("elseif (Test-XdrConsoleShortcut -Key `$key -KeyName 'a' -Alt -Control)") | Should -BeTrue
        $content.Contains('$actionStatusPanelVisible = -not $actionStatusPanelVisible') | Should -BeTrue
        $content.Contains('Set-XdrLiveActionPanelVisibility -Visible $actionStatusPanelVisible') | Should -BeTrue
        $content.Contains('Action Status panel hidden. Switched to 50-50 compact layout.') | Should -BeTrue
        $nonIncidentTabContent.Contains('Input debug (Ctrl+Alt+K): $($Context.Diagnostics.InputDebugEnabled)') | Should -BeTrue
        $content.Contains("elseif ((-not `$isAltPressed -and -not `$isCtrlPressed -and `$keyChar -eq 'q') -or (`$isCtrlPressed -and -not `$isAltPressed -and `$keyChar -eq 'q'))") | Should -BeTrue
        $content.Contains("elseif (`$key.Key -eq 'F5' -or (-not `$isAltPressed -and -not `$isCtrlPressed -and `$keyChar -eq 'r'))") | Should -BeTrue
        $content.Contains("elseif (`$isAltPressed -and `$isShiftPressed -and `$key.Key -eq 'L')") | Should -BeTrue
        $content.Contains('-ShowKeyboardHelpOverlay:$showKeyboardHelpOverlay') | Should -BeTrue
    }

    It 'gates Live Investigation behind the Settings experimental feature toggle' {
        $content = Get-Content -Path $script:dashboardPath -Raw
        $tabOrderContent = Get-Content -Path (Join-Path $script:privateRoot 'Get-XdrLiveTabOrder.ps1') -Raw
        $panelOrderContent = Get-Content -Path (Join-Path $script:privateRoot 'Get-XdrLivePanelOrder.ps1') -Raw
        $outerTabsContent = Get-Content -Path (Join-Path $script:privateRoot 'Get-XdrLiveOuterTabsHeader.ps1') -Raw
        $nonIncidentTabContent = Get-Content -Path (Join-Path $script:privateRoot 'Show-XdrLiveNonIncidentTab.ps1') -Raw

        $content.Contains('$tabOrder = @(Get-XdrLiveTabOrder -ExperimentalFeaturesEnabled:$context.Ui.ExperimentalFeaturesEnabled)') | Should -BeTrue
        $content.Contains('$activeTab -eq ''settings'' -and $earlyAltPressed -and $earlyKeyChar -eq ''e''') | Should -BeTrue
        $content.Contains('$activeTab -eq ''settings'' -and $isAltPressed -and $keyChar -eq ''e''') | Should -BeTrue
        $content.Contains('$context.Ui.ExperimentalFeaturesEnabled = -not [bool]$context.Ui.ExperimentalFeaturesEnabled') | Should -BeTrue
        $tabOrderContent.Contains('$tabOrder = @(''welcome'', ''incidents'', ''hunting'', ''query_library'', ''quarantine'')') | Should -BeTrue
        $tabOrderContent.Contains("if (`$ExperimentalFeaturesEnabled.IsPresent)") | Should -BeTrue
        $tabOrderContent.Contains("`$tabOrder += 'live_investigation'") | Should -BeTrue
        $outerTabsContent.Contains("'live_investigation' { 'Live Investigation' }") | Should -BeTrue
        $panelOrderContent.Contains("'live_investigation' { @('live_investigation_devices', 'live_investigation_session', 'live_investigation_activity', 'live_investigation_actions') }") | Should -BeTrue
        $nonIncidentTabContent.Contains("'live_investigation' {") | Should -BeTrue
        $nonIncidentTabContent.Contains('Experimental features: $experimentalFeatureStatus') | Should -BeTrue
        $nonIncidentTabContent.Contains('(Alt+E) $experimentalFeatureAction') | Should -BeTrue
        $nonIncidentTabContent.Contains('Live Investigation stays hidden until experimental features are enabled.') | Should -BeTrue
        $nonIncidentTabContent.Contains("'Use Get-XdrLiveInvestigationDevice to find onboarded devices.'") | Should -BeTrue
        $nonIncidentTabContent.Contains("'Start-XdrLiveInvestigation submits Live Response commands with confirmation.'") | Should -BeTrue
    }

    It 'captures last input diagnostics for live troubleshooting' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('Set-XdrLastInputDiagnostics -Context $context') | Should -BeTrue
        $content.Contains('-SelectedQueryIndex $selectedQueryIndex') | Should -BeTrue
        $content.Contains('-SelectedQuery $selectedQuery -SelectedEntity $selectedEntity') | Should -BeTrue
    }

    It 'keeps cached incidents visible while refresh is in progress' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('$hasVisibleIncidentData = @($context.Data.Incidents).Count -gt 0') | Should -BeTrue
        $content.Contains('if (-not $hasVisibleIncidentData) {') | Should -BeTrue
        $content.Contains('Sync-XdrLiveCachedDataToIncidents -Incidents $context.Data.Incidents') | Should -BeTrue
        $content.Contains('Restore-XdrLiveCachedAlertsForIncident -IncidentId ([string]$selectedIncident.IncidentId)') | Should -BeTrue
    }

    It 'queues alert prefetching after incident load and drains it through the concurrency-limited runner' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('Start-XdrLiveAlertLoadJob -Incident $selectedIncident -RestoreSelectionOnCompletion -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId') | Should -BeTrue
        $content.Contains('Add-XdrLiveAlertPreloads -Incidents $context.Data.Incidents -AlertPreloadQueue $alertPreloadQueue -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId') | Should -BeTrue
        $content.Contains('Start-XdrLiveQueuedAlertPreloads -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -MaxAlertLoadJobs $maxAlertLoadJobs -AlertPreloadQueue $alertPreloadQueue -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId -LogPath $dashboardLogPath') | Should -BeTrue
    }

    It 'starts entity extraction only when the entities tab is visible' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("if (`$selectedIncidentDetailsTab -eq 'entities' -and `$selectedIncident) {") | Should -BeTrue
        $content.Contains('Start-XdrLiveEntityExtraction -Incident $selectedIncident') | Should -BeTrue
        $content.Contains("if (`$selectedIncidentDetailsTab -eq 'entities' -and `$cachedAlertCount -ne `$selectedIncidentAlertCount -and -not `$entityLoadJobsByIncidentId.ContainsKey(`$selectedIncidentId))") | Should -BeTrue
    }

    It 'starts a restoring alert load for the initially selected incident when alerts are not cached' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('Clear-XdrLiveVisibleAlerts -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId)') | Should -BeTrue
        $content.Contains("Set-LiveStatusMessage -Context `$context -Message 'Press Enter to load alerts for the selected incident.' -Level 'info'") | Should -BeTrue
    }

    It 'does not load alerts automatically during incident list navigation' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('Start-XdrLiveAlertLoadJob -Incident $selectedIncident -RestoreSelectionOnCompletion -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId | Out-Null') | Should -BeFalse
        $content.Contains("Set-LiveStatusMessage -Context `$context -Message 'Press Enter to load alerts for the selected incident.' -Level 'info'") | Should -BeTrue
    }

    It 'logs periodic live-loop health for freeze diagnostics' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('$lastLoopHealthLogAt = [datetime]::MinValue') | Should -BeTrue
        $content.Contains('Loop heartbeat. Count=$heartbeatCounter ActiveTab=$activeTab ActivePanel=$activePanel DataLoaded=$dataLoaded') | Should -BeTrue
    }

    It 'throttles each live-loop iteration even when a branch skips the render tail' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('$lastLoopStartedAt = [datetime]::MinValue') | Should -BeTrue
        $content.Contains('$remainingDelayMs = [int]$context.Ui.RefreshIntervalMs - $loopElapsedMs') | Should -BeTrue
        $content.Contains('Start-Sleep -Milliseconds $remainingDelayMs') | Should -BeTrue
    }

    It 'falls through to render incidents immediately after initial load completes' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $loadCompleteIndex = $content.LastIndexOf('$pendingRefreshIncidentId = $null')
        $autoRefreshIndex = $content.IndexOf('$autoRefreshBlocked =')
        $loadCompleteIndex | Should -BeGreaterThan -1
        $autoRefreshIndex | Should -BeGreaterThan $loadCompleteIndex
        $postLoadBlock = $content.Substring($loadCompleteIndex, $autoRefreshIndex - $loadCompleteIndex)
        $postLoadBlock | Should -Not -Match '(?m)^\s*continue\s*$'
    }

    It 'loads incidents independently of the active tab and keeps bottom help fresh while loading' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $startLoadIndex = $content.IndexOf("Write-XdrLiveDashboardLog -LogPath `$dashboardLogPath -Message 'Starting background incident load.'")
        $activeTabCheckIndex = $content.IndexOf("if (`$activeTab -eq 'incidents')", $startLoadIndex)
        $startLoadIndex | Should -BeGreaterThan -1
        $activeTabCheckIndex | Should -BeGreaterThan $startLoadIndex
        $content.Substring($startLoadIndex, $activeTabCheckIndex - $startLoadIndex) | Should -Not -Match "activeTab -eq 'incidents'"
        $content.Contains('Show-XdrLiveNonIncidentTab -Layout $layout -ActiveTab $activeTab') | Should -BeTrue
        $content.Contains('-ActionPanelVisible $actionStatusPanelVisible') | Should -BeTrue
    }

    It 'updates visible alert panel state by reference when incidents change or cached alerts are restored' {
        $content = Get-Content -Path $script:dashboardPath -Raw
        $syncContent = Get-Content -Path (Join-Path $script:privateRoot 'Sync-XdrLiveVisibleAlertsFromContext.ps1') -Raw
        $clearContent = Get-Content -Path (Join-Path $script:privateRoot 'Clear-XdrLiveVisibleAlerts.ps1') -Raw

        $syncContent.Contains('[ref]$VisibleAlerts') | Should -BeTrue
        $syncContent.Contains('[ref]$VisibleAlertIncidentId') | Should -BeTrue
        $clearContent.Contains('[ref]$VisibleAlerts') | Should -BeTrue
        $clearContent.Contains('[ref]$VisibleAlertIncidentId') | Should -BeTrue
        $content.Contains('Clear-XdrLiveVisibleAlerts -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId)') | Should -BeTrue
        $content.Contains('Sync-XdrLiveVisibleAlertsFromContext -Context $context -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -Incident $selectedIncident') | Should -BeTrue
    }

    It 'reconciles selected incident cached alerts into the visible alert list each tick' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('$cachedAlertsForSelectedIncident = @($alertsByIncidentId[$selectedIncidentId])') | Should -BeTrue
        $content.Contains('$visibleAlertSignature = Get-XdrAlertListSignature -Alerts @($visibleAlerts)') | Should -BeTrue
        $content.Contains('$cachedAlertSignature = Get-XdrAlertListSignature -Alerts $cachedAlertsForSelectedIncident') | Should -BeTrue
        $content.Contains('if ([string]$visibleAlertIncidentId -ne $selectedIncidentId -or @($visibleAlerts).Count -ne $cachedAlertsForSelectedIncident.Count -or $visibleAlertSignature -ne $cachedAlertSignature) {') | Should -BeTrue
        $content.Contains('Restore-XdrLiveCachedAlertsForIncident -IncidentId $selectedIncidentId -AlertsByIncidentId $alertsByIncidentId -Context $context -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex) -LogPath $dashboardLogPath | Out-Null') | Should -BeTrue
        $content.Contains('Sync-XdrLiveVisibleAlertsFromContext -Context $context -VisibleAlerts ([ref]$visibleAlerts) -VisibleAlertIncidentId ([ref]$visibleAlertIncidentId) -Incident $selectedIncident') | Should -BeTrue
    }

    It 'does not clear the selected incident on each loaded live-loop tick' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $loadedBranchIndex = $content.IndexOf('elseif (@($context.Data.Incidents).Count -gt 0) {')
        $emptyBranchIndex = $content.IndexOf('else {', $loadedBranchIndex)
        $pendingRefreshIndex = $content.IndexOf('$pendingRefreshIncidentId = $null', $loadedBranchIndex)
        $loadedBranchIndex | Should -BeGreaterThan -1
        $emptyBranchIndex | Should -BeGreaterThan $loadedBranchIndex
        $pendingRefreshIndex | Should -BeGreaterThan $emptyBranchIndex
        $loadedBranch = $content.Substring($loadedBranchIndex, $emptyBranchIndex - $loadedBranchIndex)
        $emptyBranch = $content.Substring($emptyBranchIndex, $pendingRefreshIndex - $emptyBranchIndex)

        $loadedBranch | Should -Match '\$selectedIncident\s*=\s*\$context\.Data\.Incidents\[\$selectedIndex\]'
        $loadedBranch | Should -Not -Match '\$selectedIncident\s*=\s*\$null'
        $emptyBranch | Should -Match '\$selectedIncident\s*=\s*\$null'
    }

    It 'shows cache status and force reload actions in the dashboard wiring' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('-SelectedIncident $selectedIncident -PendingIncidentResolution') | Should -BeTrue
        $content.Contains("(Alt+Shift+L) Reload alerts") | Should -BeTrue
        $content.Contains("Shortcut = 'reload-alerts'") | Should -BeTrue
    }

    It 'uses shortened action labels to avoid wrapping in the action panel' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("(Alt+A) Assign Inc. to me") | Should -BeTrue
        $content.Contains("(Alt+U) Unassign Inc.") | Should -BeTrue
        $content.Contains('$shortcut Set Inc. to $statusLabel') | Should -BeTrue
        $content.Contains("(Alt+K) Classify Inc.") | Should -BeTrue
        $content.Contains("(Alt+C) Comment on Inc.") | Should -BeTrue
        $content.Contains("(Alt+L) Load alerts") | Should -BeTrue
        $content.Contains('$shortcut Set Alert to $statusLabel') | Should -BeTrue
    }

    It 'loads query catalog during startup and surfaces catalog errors through the live status message' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('$context.Data.QueryCatalog = @(Get-XdrQueryCatalog)') | Should -BeTrue
        $content.Contains('Set-LiveStatusMessage -Context $context -Message $catalogErrorMessage -Level ''error''') | Should -BeTrue
    }

    It 'supports hunting mode with query catalog preview results and execution shortcuts' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("`$isQueryMode = `$false") | Should -BeTrue
        $content.Contains('Set-XdrLiveActiveTab -TabName') | Should -BeTrue
        $content.Contains("`$selectedQueryIndex = 0") | Should -BeTrue
        $content.Contains("`$selectedQueryResult = `$null") | Should -BeTrue
        $content.Contains("`$queryResultsByCacheKey = @{}") | Should -BeTrue
        $content.Contains("elseif (`$isAltPressed -and `$keyChar -eq 'h')") | Should -BeTrue
        $content.Contains("elseif (`$isQueryMode -and `$isAltPressed -and `$keyChar -eq 'x')") | Should -BeTrue
        $content.Contains("Set-XdrLiveActiveTab -TabName 'hunting'") | Should -BeTrue
        $content.Contains("Set-XdrLiveActiveTab -TabName 'incidents'") | Should -BeTrue
        $content.Contains("elseif (`$isQueryMode -and `$key.Key -eq 'DownArrow' -and `$context.Data.QueryCatalog.Count -gt 0 -and `$activePanel -ne 'query_actions')") | Should -BeTrue
        $content.Contains("elseif (`$isQueryMode -and `$key.Key -eq 'UpArrow' -and `$context.Data.QueryCatalog.Count -gt 0 -and `$activePanel -ne 'query_actions')") | Should -BeTrue
        (Get-Content -Path (Join-Path $script:privateRoot 'Invoke-XdrLiveSelectedQueryExecution.ps1') -Raw).Contains('Start-XdrLiveQueryJob -Query $SelectedQuery -ModulePath $ModulePath -Context $Context -ExistingJob $QueryExecutionJob.Value -LogPath $LogPath') | Should -BeTrue
        $content.Contains('Invoke-XdrLiveQueryJobProcessing -QueryJob ([ref]$queryExecutionJob) -QueryResultsByCacheKey $queryResultsByCacheKey -Context $context -SelectedQuery $selectedQuery -SelectedQueryResult ([ref]$selectedQueryResult)') | Should -BeTrue
        (Get-Content -Path (Join-Path $script:privateRoot 'Sync-XdrSelectedQuery.ps1') -Raw).Contains('Resolve-XdrQueryParameters -Query $SelectedQuery.Value -Context $Context') | Should -BeTrue
        (Get-Content -Path (Join-Path $script:privateRoot 'Sync-XdrSelectedQuery.ps1') -Raw).Contains('Get-XdrQueryResultCacheKey -QueryId ([string]$SelectedQuery.Value.id) -ContextSnapshot ([pscustomobject]$parameterResolution.Parameters)') | Should -BeTrue
        (Get-Content -Path (Join-Path $script:privateRoot 'Sync-XdrSelectedQuery.ps1') -Raw).Contains('$SelectedQueryResult.Value = if (-not [string]::IsNullOrWhiteSpace([string]$selectedQueryCacheKey) -and $QueryResultsByCacheKey.ContainsKey([string]$selectedQueryCacheKey))') | Should -BeTrue
        $content.Contains("elseif (`$isQueryMode -and `$key.Key -eq 'Enter' -and `$activePanel -eq 'query_catalog') {") | Should -BeTrue
        $content.Contains('Invoke-XdrLiveSelectedQueryExecution -SelectedQuery $selectedQuery') | Should -BeTrue
        $content.Contains('-Title "Query Catalog ($(@($context.Data.QueryCatalog).Count))"') | Should -BeTrue
        $content.Contains("-Title 'Query Preview'") | Should -BeTrue
        $content.Contains("-Title 'Query Results'") | Should -BeTrue
        $content.Contains('-Title "Activity Log ($($queryRunHistory.Count))"') | Should -BeTrue
        $content.Contains("-Title 'Query Actions'") | Should -BeTrue
        $content.Contains("'(Alt+X) Execute selected query'") | Should -BeTrue
        $content.Contains("'(Alt+H) Return to incident workflow'") | Should -BeTrue
        $content.Contains('Query execution in progress') | Should -BeTrue
        $content.Contains("elseif (-not `$selectedIncident -and -not `$isQueryMode) {") | Should -BeTrue
        (Get-Content -Path (Join-Path $script:privateRoot 'Get-XdrQueryContextGuidance.ps1') -Raw).Contains('Manual UserId entry is not implemented yet.') | Should -BeTrue
        $content.Contains('Set-LiveStatusMessage -Context $context -Message "Switched to Hunting tab for ${selectedEntityTypeLabel}: $selectedEntityLabel" -Level ''info''') | Should -BeTrue
        $content.Contains("`$queryCatalogLines += ''") | Should -BeTrue
    }

    It 'renders hunting panels only when the Hunting tab is active' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("if (`$activeTab -eq 'hunting') {") | Should -BeTrue
        $content.Contains("if (`$activeTab -in @('incidents', 'hunting')) {") | Should -BeTrue
        $content.Contains("Set-XdrLiveActiveTab -TabName 'hunting'") | Should -BeTrue
    }

    It 'keeps confirmation prompts keyboard-accessible with Y/N/Esc/Enter' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('if ($pendingQuitConfirmation) {') | Should -BeTrue
        $content.Contains("if ((-not `$isAltPressed -and -not `$isCtrlPressed -and `$keyChar -eq 'y') -or `$key.Key -eq 'Enter') {") | Should -BeTrue
        $content.Contains("if ((-not `$isAltPressed -and -not `$isCtrlPressed -and `$keyChar -eq 'n') -or `$key.Key -eq 'Escape') {") | Should -BeTrue
        $content.Contains('elseif ($pendingConfirmation) {') | Should -BeTrue
        $content.Contains("if (-not `$isAltPressed -and -not `$isCtrlPressed -and `$keyChar -eq 'y') {") | Should -BeTrue
        $content.Contains("elseif (`$key.Key -eq 'Enter') {") | Should -BeTrue
        $content.Contains("elseif ((-not `$isAltPressed -and -not `$isCtrlPressed -and `$keyChar -eq 'n') -or `$key.Key -eq 'Escape') {") | Should -BeTrue
    }

    Context 'comment-based help' {
        It 'has a Synopsis' {
            (Get-Help Start-PwshXdrLiveDashboard).Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'has a Description' {
            (Get-Help Start-PwshXdrLiveDashboard).Description | Should -Not -BeNullOrEmpty
        }
    }
}
