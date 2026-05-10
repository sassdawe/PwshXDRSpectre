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
        [switch]$UseDeviceCode
    )

    $context = New-XdrRuntimeContext -TenantId $TenantId -ClientId $ClientId -Mode 'live' -ThemeColor 'Orange1'

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
            New-SpectreLayout -Name 'incident_content' -Ratio 5 -Columns @(
                (New-SpectreLayout -Name 'incidents' -Ratio 2 -Data 'empty'),
                (New-SpectreLayout -Name 'incident_details' -Ratio 4 -Data 'empty')
            )
        ),
        (
            New-SpectreLayout -Name 'alert_content' -Ratio 5 -Columns @(
                (New-SpectreLayout -Name 'alerts' -Ratio 3 -Data 'empty'),
                (New-SpectreLayout -Name 'alert_details' -Ratio 4 -Data 'empty'),
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
        $showEntityPanel = $false
        $actionEntries = @()
        $pendingConfirmation = $null
        $pendingTextInput = $null
        $pendingIncidentResolution = $null
        $pendingIncidentClassification = $null
        $pendingIncidentComment = $null
        $activePanelBeforeResolution = $null
        $activePanelBeforeClassification = $null
        $activePanelBeforeComment = $null
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

            $entityLoadJobsByIncidentId[$incidentId] = Start-ThreadJob -ScriptBlock {
                param(
                    [string]$ModulePath,
                    [object]$IncidentData,
                    [object[]]$AlertData
                )

                Import-Module $ModulePath -Force | Out-Null
                Get-XdrIncidentEntities -Incident $IncidentData -Alerts $AlertData
            } -ArgumentList $modulePath, $Incident, $alertsForIncident
        }

        while ($true) {
            if (-not $authAttempted) {
                $layout['header'].Update((Get-XdrLiveHeaderPanel -Context $context -ScriptRoot $PSScriptRoot)) | Out-Null
            $layout['incidents'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
            $layout['incident_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title 'Incident Details (Alt+E entities)' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
            $layout['alerts'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alerts' -Title 'Alert List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
            $layout['alert_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
            $layout['action_status'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
            $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt)) -Expand)) | Out-Null
                $LiveContext.Refresh()

                $authAttempted = $true
            $layout['incidents'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Authenticating with Microsoft Graph...' -Expand)) | Out-Null
            $layout['incident_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title 'Incident Details (Alt+E entities)' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Authenticating with Microsoft Graph...' -Expand)) | Out-Null
            $layout['action_status'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Authenticating with Microsoft Graph...' -Expand)) | Out-Null
            $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt)) -Expand)) | Out-Null
                $LiveContext.Refresh()

                $connectResult = Connect-XdrSession -Context $context -UseDeviceCode:$UseDeviceCode.IsPresent
                if (-not $connectResult.Success) {
                    $fatalErrorMessage = $connectResult.Message
                }
                else {
                    $authSucceeded = $true
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
                $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt)) -Expand)) | Out-Null
                $LiveContext.Refresh()

                $keyOnError = Get-XdrLastKeyPressed
                if ($keyOnError -and $keyOnError.Key -eq 'Escape') {
                    return
                }

                Start-Sleep -Milliseconds $context.Ui.RefreshIntervalMs
                continue
            }

            if (-not $dataLoaded) {
                $layout['header'].Update((Get-XdrLiveHeaderPanel -Context $context -ScriptRoot $PSScriptRoot)) | Out-Null
                $layout['incidents'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Loading incidents...' -Expand)) | Out-Null
                $layout['incident_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title 'Incident Details (Alt+E entities)' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Loading incidents...' -Expand)) | Out-Null
                $layout['action_status'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Loading capabilities...' -Expand)) | Out-Null
                $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt)) -Expand)) | Out-Null
                $LiveContext.Refresh()

                $incidentsResult = Get-XdrIncidents -Context $context -Limit $Limit
                if (-not $incidentsResult.Success) {
                    $fatalErrorMessage = $incidentsResult.Message
                    $authSucceeded = $false
                    continue
                }

                $dataLoaded = $true
                if ($context.Data.Incidents.Count -gt 0) {
                    $selectedIndex = 0
                    $selectedIncident = $context.Data.Incidents[$selectedIndex]
                    $context.Selection.Incident = $selectedIncident
                    $selectedEntityIndex = 0
                    $selectedEntity = $null
                    $context.Selection.Entity = $null
                    & $startEntityExtraction $selectedIncident
                }

                Add-XdrLiveAlertPreloads -Incidents $context.Data.Incidents -AlertPreloadQueue $alertPreloadQueue -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId
                Start-XdrLiveQueuedAlertPreloads -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -MaxAlertLoadJobs $maxAlertLoadJobs -AlertPreloadQueue $alertPreloadQueue -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId
                continue
            }

            Invoke-XdrLiveAlertLoadJobProcessing -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertsByIncidentId $alertsByIncidentId -SelectedIncident $selectedIncident -Context $context -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex)
            Start-XdrLiveQueuedAlertPreloads -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -MaxAlertLoadJobs $maxAlertLoadJobs -AlertPreloadQueue $alertPreloadQueue -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId

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

            # For text input mode, capture all buffered keys to prevent character loss during rapid typing
            # For other modes, capture only the last key (navigation, selections)
            $keys = if (
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

                if ($null -ne $pendingIncidentResolution) {
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
                elseif ($isAltPressed -and $keyChar -eq 'e') {
                    $showEntityPanel = $true
                    $activePanel = 'incident_details'
                    $activePanelIndex = [array]::IndexOf($panelOrder, 'incident_details')
                    $context.Selection.Panel = $activePanel
                    Set-LiveStatusMessage -Context $context -Message 'Showing related entities panel.' -Level 'info'
                }
                elseif ($isAltPressed -and $keyChar -eq 'd') {
                    $showEntityPanel = $false
                    $activePanel = 'incident_details'
                    $activePanelIndex = [array]::IndexOf($panelOrder, 'incident_details')
                    $context.Selection.Panel = $activePanel
                    Set-LiveStatusMessage -Context $context -Message 'Showing incident details panel.' -Level 'info'
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
                    if ($isShiftPressed) {
                        $activePanelIndex = ($activePanelIndex - 1 + $panelOrder.Count) % $panelOrder.Count
                    }
                    else {
                        $activePanelIndex = ($activePanelIndex + 1) % $panelOrder.Count
                    }

                    $activePanel = $panelOrder[$activePanelIndex]
                    $context.Selection.Panel = $activePanel
                }
                elseif ($key.Key -eq 'F5') {
                    $dataLoaded = $false
                    $context.Data.Incidents = @()
                    $context.Data.Alerts = @()
                    $context.Data.Entities = @()
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
                    Set-LiveStatusMessage -Context $context -Message 'Refreshing incidents and alert cache...' -Level 'info'
                    continue
                }

                if ($keyHandled) {
                    # Modal workflows consume the current keypress so it cannot also trigger
                    # normal panel actions later in the same loop iteration.
                }

                elseif (-not $selectedIncident) {
                    continue
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
                        Start-XdrLiveAlertLoadJob -Incident $selectedIncident -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId | Out-Null
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
                        Start-XdrLiveAlertLoadJob -Incident $selectedIncident -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId | Out-Null
                    }

                    if ($entitiesByIncidentId.ContainsKey($incidentId)) {
                        $context.Data.Entities = @($entitiesByIncidentId[$incidentId])
                    }
                    else {
                        $context.Data.Entities = @()
                    }
                    & $startEntityExtraction $selectedIncident
                }
                elseif ($key.Key -eq 'DownArrow' -and $activePanel -eq 'alerts' -and $context.Data.Alerts.Count -gt 0) {
                    $selectedAlertIndex = ($selectedAlertIndex + 1) % $context.Data.Alerts.Count
                    $selectedAlert = $context.Data.Alerts[$selectedAlertIndex]
                    $context.Selection.Alert = $selectedAlert
                    $selectedAlertIdByIncidentId[[string]$selectedIncident.IncidentId] = [string]$selectedAlert.AlertId
                }
                elseif ($key.Key -eq 'UpArrow' -and $activePanel -eq 'alerts' -and $context.Data.Alerts.Count -gt 0) {
                    $selectedAlertIndex = ($selectedAlertIndex - 1 + $context.Data.Alerts.Count) % $context.Data.Alerts.Count
                    $selectedAlert = $context.Data.Alerts[$selectedAlertIndex]
                    $context.Selection.Alert = $selectedAlert
                    $selectedAlertIdByIncidentId[[string]$selectedIncident.IncidentId] = [string]$selectedAlert.AlertId
                }
                elseif ($showEntityPanel -and $key.Key -eq 'DownArrow' -and $activePanel -eq 'incident_details' -and $context.Data.Entities.Count -gt 0) {
                    $selectedEntityIndex = ($selectedEntityIndex + 1) % $context.Data.Entities.Count
                    $selectedEntity = $context.Data.Entities[$selectedEntityIndex]
                    $context.Selection.Entity = $selectedEntity
                }
                elseif ($showEntityPanel -and $key.Key -eq 'UpArrow' -and $activePanel -eq 'incident_details' -and $context.Data.Entities.Count -gt 0) {
                    $selectedEntityIndex = ($selectedEntityIndex - 1 + $context.Data.Entities.Count) % $context.Data.Entities.Count
                    $selectedEntity = $context.Data.Entities[$selectedEntityIndex]
                    $context.Selection.Entity = $selectedEntity
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
                            if (Start-XdrLiveAlertLoadJob -Incident $selectedIncident -ModulePath $modulePath -Context $context -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId) {
                                Set-LiveStatusMessage -Context $context -Message 'Loading alerts in background...' -Level 'info'
                            }
                        }
                    }
                    if ($context.Data.Alerts.Count -gt 0) {
                        $activePanel = 'alerts'
                        $activePanelIndex = [array]::IndexOf($panelOrder, 'alerts')
                        $context.Selection.Panel = $activePanel
                    }
                }
                elseif ($key.Key -eq 'Enter' -and $activePanel -eq 'action_status' -and $actionEntries.Count -gt 0) {
                    $selectedAction = $actionEntries[$selectedActionIndex]
                    if ($selectedAction.IsEnabled) {
                        Invoke-XdrLiveActionShortcut -Shortcut $selectedAction.Shortcut -Context $context -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -TriageOptions $triageOptions -PanelOrder $panelOrder -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -ActivePanelBeforeResolution ([ref]$activePanelBeforeResolution) -PendingConfirmation ([ref]$pendingConfirmation) -PendingTextInput ([ref]$pendingTextInput) -PendingIncidentResolution ([ref]$pendingIncidentResolution) -ActivePanelBeforeClassification ([ref]$activePanelBeforeClassification) -PendingIncidentClassification ([ref]$pendingIncidentClassification) -ActivePanelBeforeComment ([ref]$activePanelBeforeComment) -PendingIncidentComment ([ref]$pendingIncidentComment) -ModulePath $modulePath -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlertIndex ([ref]$selectedAlertIndex)
                    }
                    else {
                        Set-LiveStatusMessage -Context $context -Message "$($selectedAction.Label) is not available right now." -Level 'warning'
                    }
                }
                elseif ($isAltPressed -and $keyChar -in @('a', 'u', 'o', 'i', 'r', 'k', 'c', 'l', 'n', 'p', 'm')) {
                    Invoke-XdrLiveActionShortcut -Shortcut $keyChar -Context $context -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -TriageOptions $triageOptions -PanelOrder $panelOrder -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -ActivePanelBeforeResolution ([ref]$activePanelBeforeResolution) -PendingConfirmation ([ref]$pendingConfirmation) -PendingTextInput ([ref]$pendingTextInput) -PendingIncidentResolution ([ref]$pendingIncidentResolution) -ActivePanelBeforeClassification ([ref]$activePanelBeforeClassification) -PendingIncidentClassification ([ref]$pendingIncidentClassification) -ActivePanelBeforeComment ([ref]$activePanelBeforeComment) -PendingIncidentComment ([ref]$pendingIncidentComment) -ModulePath $modulePath -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlertIndex ([ref]$selectedAlertIndex)
                }
            }  # end foreach ($key in $keys)

            if (-not $context.Data.Incidents) {
                $selectedEntity = $null
                $context.Selection.Entity = $null
                $layout['header'].Update((Get-XdrLiveHeaderPanel -Context $context -ScriptRoot $PSScriptRoot)) | Out-Null
                $layout['incidents'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No incidents found. Press Ctrl+C to exit.' -Expand)) | Out-Null
                $emptyIncidentDetailsTitle = if ($showEntityPanel) { 'Related Entities (Alt+D details)' } else { 'Incident Details (Alt+E entities)' }
                $emptyIncidentDetailsData = if ($showEntityPanel) { 'No incident selected. Press Alt+D for details view.' } else { 'No incident selected.' }
                $layout['incident_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title $emptyIncidentDetailsTitle -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data $emptyIncidentDetailsData -Expand)) | Out-Null
                $layout['alerts'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alerts' -Title 'Alert List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No incident selected.' -Expand)) | Out-Null
                $layout['alert_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No alert selected.' -Expand)) | Out-Null
                $layout['action_status'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No incident selected.' -Expand)) | Out-Null
                $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt)) -Expand)) | Out-Null
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

            $incidentDetails = if ($showEntityPanel) {
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

                    $relatedAlertRows = @($context.Data.Alerts | Where-Object {
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

                    for ($entityIdx = 0; $entityIdx -lt $entityEntries.Count; $entityIdx++) {
                        $entity = $entityEntries[$entityIdx]
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
                $entityLines += '[grey]Alt+D to return to Incident Details[/]'

                Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title 'Related Entities (Alt+D details)' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($entityLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'incident_details' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'incident_details' -ActivePanel $activePanel) -Expand
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
                } | Format-SpectreJson | Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title 'Incident Details (Alt+E entities)' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Color (Get-PanelBorderColor -PanelName 'incident_details' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'incident_details' -ActivePanel $activePanel) -Expand
            }

            $alertLines = if ($context.Data.Alerts) {
                @('Sev Title                                         Status')
                @($context.Data.Alerts | ForEach-Object {
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

            $alertsPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alerts' -Title "Alert List ($($context.Data.Alerts.Count))" -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data (($alertLines | Out-String)) -Color (Get-PanelBorderColor -PanelName 'alerts' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'alerts' -ActivePanel $activePanel) -Expand

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

            if ($showEntityPanel) {
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

            $contextHelpLine = (Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation -PendingTextInput $pendingTextInput -PendingIncidentResolution $pendingIncidentResolution -PendingIncidentClassification $pendingIncidentClassification -PendingIncidentComment $pendingIncidentComment) -join ' | '
            $helpHeaderText = "Help | $contextHelpLine"
            $helpPanel = Format-SpectrePanel -Header "[white]$helpHeaderText[/]" -Data (Get-XdrLiveHelpPanelContent -Context $context -PendingIncidentResolution $pendingIncidentResolution -PendingTextInput $pendingTextInput -PendingConfirmation $pendingConfirmation -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -AlertPreloadQueue $alertPreloadQueue -PrefetchCompletedAt ([ref]$prefetchCompletedAt)) -Color (Get-PanelBorderColor -PanelName 'help' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Border (Get-PanelBorderStyle -PanelName 'help' -ActivePanel $activePanel) -Expand

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
