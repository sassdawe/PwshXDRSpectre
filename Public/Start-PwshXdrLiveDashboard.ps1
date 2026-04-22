function Start-PwshXdrLiveDashboard {
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

    function ConvertTo-SafeSpectreText {
        param(
            [AllowNull()]
            [object]$Value
        )

        if ($null -eq $Value) {
            return ''
        }

        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) {
            return ''
        }

        return Get-SpectreEscapedText $text
    }

    function ConvertTo-SafePanelData {
        param(
            [AllowNull()]
            [object]$Value
        )

        if ($null -eq $Value) {
            return ' '
        }

        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) {
            return ' '
        }

        return Get-SpectreEscapedText $text
    }

    function New-ActionStateLine {
        param(
            [string]$Label,
            [string[]]$Reasons
        )

        $normalizedLabel = [string]$Label

        if (-not $Reasons -or $Reasons.Count -eq 0) {
            return $normalizedLabel
        }

        $inactiveLabel = [regex]::Replace($normalizedLabel, '\((?:Alt\+)?[A-Z]\)', '(ⓧ)', 1)
        if ($inactiveLabel -eq $normalizedLabel) {
            return "(ⓧ) $normalizedLabel"
        }

        return $inactiveLabel
    }

    function Get-PanelHeaderMarkup {
        param(
            [string]$PanelName,
            [string]$Title,
            [string]$ActivePanel,
            [string]$Color
        )

        if ($PanelName -eq $ActivePanel) {
            return "[bold ${Color}]$Title (ACTIVE)[/]"
        }

        return "[white]$Title[/]"
    }

    function Get-PanelBorderColor {
        param(
            [string]$PanelName,
            [string]$ActivePanel,
            [string]$AccentColor,
            [string]$BaseColor = 'deepskyblue1'
        )

        if ($PanelName -eq $ActivePanel) {
            return $AccentColor
        }

        return $BaseColor
    }

    function Set-LiveStatusMessage {
        param(
            [string]$Message,
            [ValidateSet('info', 'success', 'warning', 'error')]
            [string]$Level = 'info'
        )

        if ([string]::IsNullOrWhiteSpace($Message)) {
            return
        }

        $prefix = switch ($Level) {
            'success' { 'OK' }
            'warning' { 'WARN' }
            'error' { 'ERR' }
            default { 'INFO' }
        }

        $context.Ui.StatusMessage = "$prefix $Message"
        $context.Ui.LastNotification = Get-Date
    }

    function Set-StatusFromResult {
        param(
            [object]$Result,
            [string]$PendingMessage
        )

        if (-not $Result) {
            return
        }

        if ($Result.Data -and $Result.Data.ConfirmationRequired) {
            Set-LiveStatusMessage -Message $(if ($PendingMessage) { $PendingMessage } else { $Result.Message }) -Level 'warning'
            return
        }

        if ($Result.Success) {
            Set-LiveStatusMessage -Message $Result.Message -Level 'success'
            return
        }

        Set-LiveStatusMessage -Message $Result.Message -Level 'error'
    }

    function Get-ContextAwareHelpLines {
        param(
            [string]$ActivePanel,
            [object]$SelectedIncident,
            [object]$SelectedAlert,
            [object]$PendingConfirmation,
            [object]$PendingTextInput,
            [object]$PendingIncidentResolution
        )

        if ($null -ne $PendingIncidentResolution) {
            return @('Incident resolution workflow active | PgUp/PgDn step switch | Use Incident Resolution panel | Esc cancel')
        }

        if ($null -ne $PendingTextInput) {
            return @('Comment input mode | Type text | Enter submit | Backspace edit | Esc cancel | Shortcuts disabled')
        }

        $baseLine = 'Alt+A/U/O/I/R/C incident | Alt+L load alerts | Alt+N/P/M alert | F5 refresh | Tab/Shift+Tab or PgUp/PgDn switch | ↑/↓ move | Enter run/load | Ctrl+Q exit'

        switch ($ActivePanel) {
            'incidents' {
                return @('↑/↓ incidents | Enter or L loads alerts | F5 refresh incidents | Tab or PgUp/PgDn switch | Ctrl+Q exit')
            }
            'incident_details' {
                return @('Alt+A/U/O/I/R/C selected incident | Alt+L or Enter loads alerts | Tab or PgUp/PgDn switch | Ctrl+Q exit')
            }
            'alerts' {
                return @('↑/↓ alerts | Alt+N/P/M selected alert | F5 refresh incidents | Tab or PgUp/PgDn switch | Ctrl+Q exit')
            }
            'alert_details' {
                return @('Alt+N/P/M selected alert | Load alerts with Alt+L/Enter if needed | Tab or PgUp/PgDn switch | Ctrl+Q exit')
            }
            'action_status' {
                return @('↑/↓ select action | Enter execute selected | Alt+A/U/O/I/R/C/L/N/P/M shortcuts | F5 refresh incidents | Tab or PgUp/PgDn switch | Ctrl+Q exit')
            }
        }

        return @($baseLine)
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
                (New-SpectreLayout -Name 'alerts' -Ratio 2 -Data 'empty'),
                (New-SpectreLayout -Name 'alert_details' -Ratio 4 -Data 'empty'),
                (New-SpectreLayout -Name 'action_status' -Ratio 3 -Data 'empty')
            )
        ),
        (New-SpectreLayout -Name 'help' -MinimumSize 3 -Ratio 1 -Data 'empty')
    )

    Invoke-SpectreLive -Data $layout -ScriptBlock {
        param([Spectre.Console.LiveDisplayContext]$LiveContext)

        $getHeaderPanel = {
            $headerColor = if (
                $context.Session -and
                $context.Session.PermissionHealth -and
                -not $context.Session.PermissionHealth.HasSufficientWritePermissions
            ) { 'red' } else { $context.Ui.ThemeColor }

            $fallbackMarkup = "[bold $headerColor]HELLO XDR SPECTRE[/]"

            $windowWidth = 0
            try {
                $windowWidth = [int]$Host.UI.RawUI.WindowSize.Width
            }
            catch {
                $windowWidth = 0
            }

            if ($windowWidth -gt 0 -and $windowWidth -lt 110) {
                return (Format-SpectrePanel -Data $fallbackMarkup -Expand)
            }

            try {
                return (Write-SpectreFigletText -Text 'Hello XDR Spectre' -Alignment 'Center' -Color $headerColor -FigletFontPath "$PSScriptRoot/../ANSI Shadow.flf" -PassThru | Format-SpectrePanel -Expand)
            }
            catch {
                return (Format-SpectrePanel -Data $fallbackMarkup -Expand)
            }
        }

        $headerPanel = & $getHeaderPanel
        $authAttempted = $false
        $authSucceeded = $false
        $dataLoaded = $false
        $fatalErrorMessage = $null

        $panelOrder = @('incidents', 'alerts', 'action_status')
        $activePanelIndex = 0
        $activePanel = $panelOrder[$activePanelIndex]
        $context.Selection.Panel = $activePanel

        $selectedIndex = 0
        $selectedAlertIndex = 0
        $selectedActionIndex = 0
        $selectedIncident = $null
        $selectedAlert = $null
        $actionEntries = @()
        $pendingConfirmation = $null
        $pendingTextInput = $null
        $pendingIncidentResolution = $null
        $activePanelBeforeResolution = $null
        $alertsByIncidentId = @{}
        $selectedAlertIdByIncidentId = @{}
        $alertLoadJobsByIncidentId = @{}
        $alertPreloadQueue = [System.Collections.Queue]::new()
        $maxAlertLoadJobs = 2
        $prefetchCompletedAt = $null
        $modulePath = Join-Path $PSScriptRoot '..' 'PwshXDRSpectre.psm1'
        $triageOptions = Get-XdrTriageOptions

        $restoreCachedAlertsForIncident = {
            param([string]$IncidentId)

            if (-not $alertsByIncidentId.ContainsKey($IncidentId)) {
                return $false
            }

            $context.Data.Alerts = @($alertsByIncidentId[$IncidentId])
            if ($context.Data.Alerts.Count -eq 0) {
                $selectedAlert = $null
                $selectedAlertIndex = 0
                $context.Selection.Alert = $null
                return $true
            }

            $selectedAlertIndex = 0
            if ($selectedAlertIdByIncidentId.ContainsKey($IncidentId)) {
                $cachedSelectedAlertId = [string]$selectedAlertIdByIncidentId[$IncidentId]
                for ($i = 0; $i -lt $context.Data.Alerts.Count; $i++) {
                    if ([string]$context.Data.Alerts[$i].AlertId -eq $cachedSelectedAlertId) {
                        $selectedAlertIndex = $i
                        break
                    }
                }
            }

            $selectedAlert = $context.Data.Alerts[$selectedAlertIndex]
            $context.Selection.Alert = $selectedAlert
            $selectedAlertIdByIncidentId[$IncidentId] = [string]$selectedAlert.AlertId
            return $true
        }

        $startAlertLoadJob = {
            param(
                [object]$Incident,
                [switch]$ForceReload
            )

            if (-not $Incident) {
                return $false
            }

            $incidentId = [string]$Incident.IncidentId
            if ([string]::IsNullOrWhiteSpace($incidentId)) {
                return $false
            }

            if (-not $ForceReload -and $alertsByIncidentId.ContainsKey($incidentId)) {
                return $false
            }

            if ($alertLoadJobsByIncidentId.ContainsKey($incidentId)) {
                return $false
            }

            $job = Start-ThreadJob -ArgumentList $modulePath, $context, $Incident, $incidentId -ScriptBlock {
                param($jobModulePath, $jobContext, $jobIncident, $jobIncidentId)

                Import-Module $jobModulePath -Force | Out-Null
                $result = Get-XdrAlerts -Context $jobContext -Incident $jobIncident
                [pscustomobject]@{
                    IncidentId = $jobIncidentId
                    Result     = $result
                }
            }

            $alertLoadJobsByIncidentId[$incidentId] = $job
            return $true
        }

        $processAlertLoadJobs = {
            foreach ($jobEntry in @($alertLoadJobsByIncidentId.GetEnumerator())) {
                $incidentId = [string]$jobEntry.Key
                $job = $jobEntry.Value
                if ($job.State -notin @('Completed', 'Failed', 'Stopped')) {
                    continue
                }

                $jobOutput = @()
                try {
                    $jobOutput = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
                }
                catch {
                    $jobOutput = @()
                }

                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                [void]$alertLoadJobsByIncidentId.Remove($incidentId)

                if ($job.State -ne 'Completed' -or $jobOutput.Count -eq 0) {
                    continue
                }

                $payload = $jobOutput[0]
                if (-not $payload.Result -or -not $payload.Result.Success) {
                    continue
                }

                $loadedAlerts = @($payload.Result.Data)
                $alertsByIncidentId[$incidentId] = $loadedAlerts

                if ($selectedIncident -and [string]$selectedIncident.IncidentId -eq $incidentId) {
                    . $restoreCachedAlertsForIncident $incidentId | Out-Null
                }
            }
        }

        $startQueuedAlertPreloads = {
            while ($alertLoadJobsByIncidentId.Count -lt $maxAlertLoadJobs -and $alertPreloadQueue.Count -gt 0) {
                $nextIncident = $alertPreloadQueue.Dequeue()
                . $startAlertLoadJob -Incident $nextIncident | Out-Null
            }
        }

        $enqueueAlertPreloads = {
            param([object[]]$Incidents)

            $alertPreloadQueue.Clear()
            foreach ($incident in @($Incidents)) {
                if (-not $incident) {
                    continue
                }

                $incidentId = [string]$incident.IncidentId
                if ([string]::IsNullOrWhiteSpace($incidentId)) {
                    continue
                }

                if ($alertsByIncidentId.ContainsKey($incidentId) -or $alertLoadJobsByIncidentId.ContainsKey($incidentId)) {
                    continue
                }

                $alertPreloadQueue.Enqueue($incident)
            }
        }

        $getAlertPrefetchIndicator = {
            $barWidth = 12
            $active = $alertLoadJobsByIncidentId.Count
            $queue = $alertPreloadQueue.Count

            $incidentIds = @($context.Data.Incidents |
                Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.IncidentId) } |
                ForEach-Object { [string]$_.IncidentId } |
                Select-Object -Unique)

            $total = $incidentIds.Count
            if ($total -eq 0) {
                $prefetchCompletedAt = $null
                return $null
            }

            $cached = 0
            foreach ($incidentId in $incidentIds) {
                if ($alertsByIncidentId.ContainsKey($incidentId)) {
                    $cached++
                }
            }

            $isPrefetchComplete = ($cached -ge $total -and $active -eq 0 -and $queue -eq 0)
            if ($isPrefetchComplete) {
                if ($null -eq $prefetchCompletedAt) {
                    $prefetchCompletedAt = Get-Date
                }
            }
            else {
                $prefetchCompletedAt = $null
            }

            if ($null -ne $prefetchCompletedAt -and ((Get-Date) - $prefetchCompletedAt).TotalMinutes -ge 1) {
                return $null
            }

            $filled = [Math]::Min($barWidth, [Math]::Floor(($cached / $total) * $barWidth))
            $bar = ('=' * $filled) + ('.' * ($barWidth - $filled))
            return "prefetch $cached/$total $bar active:$active queue:$queue"
        }

        $getHelpPanelContent = {
            if ($null -ne $pendingIncidentResolution) {
                return ' '
            }

            if ($null -ne $pendingTextInput) {
                $title = if ([string]::IsNullOrWhiteSpace([string]$pendingTextInput.Title)) {
                    'COMMENT'
                }
                else {
                    Get-SpectreEscapedText ([string]$pendingTextInput.Title)
                }

                $prompt = Get-SpectreEscapedText ([string]$pendingTextInput.Prompt)
                $inputValue = if ([string]::IsNullOrWhiteSpace([string]$pendingTextInput.Value)) { '' } else { Get-SpectreEscapedText ([string]$pendingTextInput.Value) }
                $inputDisplay = if ([string]::IsNullOrWhiteSpace($inputValue)) { '[grey]<empty>[/]' } else { "[white]$inputValue[/]" }
                return "[bold black on orange1] $title [/] [yellow]$prompt[/]`n$inputDisplay [grey](Enter submit | Esc cancel)[/]"
            }

            $prefetchRaw = [string](& $getAlertPrefetchIndicator)
            $hasPrefetchLine = -not [string]::IsNullOrWhiteSpace($prefetchRaw)
            $prefetchLine = if ($hasPrefetchLine) { Get-SpectreEscapedText $prefetchRaw } else { $null }
            $statusText = [string]$context.Ui.StatusMessage

            if ($null -ne $pendingConfirmation) {
                $statusLine = if ([string]::IsNullOrWhiteSpace($statusText)) {
                    '[bold yellow]WARN Confirmation required[/]'
                }
                else {
                    "[bold yellow]$(Get-SpectreEscapedText $statusText)[/]"
                }

                $promptText = Get-SpectreEscapedText ([string]$pendingConfirmation.Prompt)
                $confirmLine = "[bold black on yellow] CONFIRM [/] [yellow]$promptText[/] [grey]Y confirm | N or Esc cancel[/]"
                return "$statusLine`n$confirmLine"
            }

            if (-not [string]::IsNullOrWhiteSpace($statusText)) {
                if ($statusText -match '^(OK|WARN|ERR|INFO)\s+(.+)$') {
                    $statusCode = $Matches[1]
                    $statusMessageText = Get-SpectreEscapedText $Matches[2]
                    $statusColor = switch ($statusCode) {
                        'OK' { 'green' }
                        'WARN' { 'yellow' }
                        'ERR' { 'red' }
                        default { 'deepskyblue1' }
                    }

                    if ($hasPrefetchLine) {
                        return "[bold $statusColor]$statusCode $statusMessageText[/]`n[grey]$prefetchLine[/]"
                    }

                    return "[bold $statusColor]$statusCode $statusMessageText[/]"
                }

                if ($hasPrefetchLine) {
                    return "[white]$(Get-SpectreEscapedText $statusText)[/]`n[grey]$prefetchLine[/]"
                }

                return "[white]$(Get-SpectreEscapedText $statusText)[/]"
            }

            if ($hasPrefetchLine) {
                return "[grey]$prefetchLine[/]"
            }

            return ' '
        }

        $invokeActionShortcut = {
            param([string]$Shortcut)

            switch ($Shortcut) {
                'l' {
                    if (-not $selectedIncident) {
                        Set-LiveStatusMessage -Message 'No incident is selected for loading alerts.' -Level 'warning'
                        break
                    }

                    $incidentId = [string]$selectedIncident.IncidentId
                    if (. $restoreCachedAlertsForIncident $incidentId) {
                        Set-LiveStatusMessage -Message 'Loaded alerts from cache.' -Level 'success'
                    }
                    elseif ($alertLoadJobsByIncidentId.ContainsKey($incidentId)) {
                        Set-LiveStatusMessage -Message 'Alerts are already loading in background...' -Level 'info'
                    }
                    elseif (. $startAlertLoadJob -Incident $selectedIncident -ForceReload) {
                        Set-LiveStatusMessage -Message 'Loading alerts in background...' -Level 'info'
                    }
                    else {
                        Set-LiveStatusMessage -Message 'Unable to start alert loading for this incident.' -Level 'warning'
                    }
                }
                'a' {
                    $assignResult = Set-XdrIncidentTriage -Context $context -IncidentId $selectedIncident.IncidentId -AssignToMe
                    Set-StatusFromResult -Result $assignResult
                }
                'u' {
                    $clearResult = Set-XdrIncidentTriage -Context $context -IncidentId $selectedIncident.IncidentId -ClearAssignment
                    if ($clearResult.Data -and $clearResult.Data.ConfirmationRequired) {
                        $pendingConfirmation = [pscustomobject]@{
                            ActionName = $clearResult.Data.ActionName
                            Prompt     = $clearResult.Data.Prompt
                            Execute    = { Set-XdrIncidentTriage -Context $context -IncidentId $selectedIncident.IncidentId -ClearAssignment -SkipConfirmation }
                        }
                    }
                    Set-StatusFromResult -Result $clearResult -PendingMessage 'Confirmation required to clear the incident assignment.'
                }
                'o' {
                    $activeResult = Set-XdrIncidentTriage -Context $context -IncidentId $selectedIncident.IncidentId -Status 'Active'
                    Set-StatusFromResult -Result $activeResult
                }
                'i' {
                    $progressResult = Set-XdrIncidentTriage -Context $context -IncidentId $selectedIncident.IncidentId -Status 'In progress'
                    Set-StatusFromResult -Result $progressResult
                }
                'r' {
                    $determinationChoices = @($triageOptions.IncidentDeterminations)
                    if ($determinationChoices.Count -eq 0) {
                        Set-LiveStatusMessage -Message 'No incident determination options are configured.' -Level 'warning'
                        break
                    }

                    $activePanelBeforeResolution = $activePanel
                    $activePanel = 'action_status'
                    $activePanelIndex = [array]::IndexOf($panelOrder, 'action_status')
                    $context.Selection.Panel = $activePanel

                    $pendingTextInput = $null
                    $pendingIncidentResolution = [pscustomobject]@{
                        Step                 = 'determination'
                        DeterminationOptions = $determinationChoices
                        DeterminationIndex   = 0
                        ResolvingComment     = ''
                    }
                }
                'c' {
                    $pendingTextInput = [pscustomobject]@{
                        Mode   = 'incident_comment'
                        Title  = 'INCIDENT COMMENT'
                        Prompt = 'Enter comment for selected incident'
                        Value  = ''
                        Submit = {
                            param([string]$InputText)

                            if ([string]::IsNullOrWhiteSpace($InputText)) {
                                Set-LiveStatusMessage -Message 'Comment cannot be empty.' -Level 'warning'
                                return
                            }

                            $commentResult = Set-XdrIncidentTriage -Context $context -IncidentId $selectedIncident.IncidentId -Comment $InputText
                            Set-StatusFromResult -Result $commentResult
                        }
                    }
                }
                'n' {
                    if (-not $selectedAlert) {
                        Set-LiveStatusMessage -Message 'No alert is selected for this shortcut.' -Level 'warning'
                    }
                    else {
                        $alertNewResult = Set-XdrAlertStatus -Context $context -AlertId $selectedAlert.AlertId -Status 'New'
                        if ($alertNewResult.Data -and $alertNewResult.Data.ConfirmationRequired) {
                            $pendingConfirmation = [pscustomobject]@{
                                ActionName = $alertNewResult.Data.ActionName
                                Prompt     = $alertNewResult.Data.Prompt
                                Execute    = { Set-XdrAlertStatus -Context $context -AlertId $selectedAlert.AlertId -Status 'New' -SkipConfirmation }
                            }
                        }
                        Set-StatusFromResult -Result $alertNewResult -PendingMessage 'Confirmation required to reopen the alert.'
                    }
                }
                'p' {
                    if (-not $selectedAlert) {
                        Set-LiveStatusMessage -Message 'No alert is selected for this shortcut.' -Level 'warning'
                    }
                    else {
                        $alertProgressResult = Set-XdrAlertStatus -Context $context -AlertId $selectedAlert.AlertId -Status 'In progress'
                        Set-StatusFromResult -Result $alertProgressResult
                    }
                }
                'm' {
                    if (-not $selectedAlert) {
                        Set-LiveStatusMessage -Message 'No alert is selected for this shortcut.' -Level 'warning'
                    }
                    else {
                        $alertResolveResult = Set-XdrAlertStatus -Context $context -AlertId $selectedAlert.AlertId -Status 'Resolved'
                        if ($alertResolveResult.Data -and $alertResolveResult.Data.ConfirmationRequired) {
                            $pendingConfirmation = [pscustomobject]@{
                                ActionName = $alertResolveResult.Data.ActionName
                                Prompt     = $alertResolveResult.Data.Prompt
                                Execute    = { Set-XdrAlertStatus -Context $context -AlertId $selectedAlert.AlertId -Status 'Resolved' -SkipConfirmation }
                            }
                        }
                        Set-StatusFromResult -Result $alertResolveResult -PendingMessage 'Confirmation required to resolve the alert.'
                    }
                }
            }
        }

        while ($true) {
            if (-not $authAttempted) {
                $layout['header'].Update((& $getHeaderPanel)) | Out-Null
            $layout['incidents'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
            $layout['incident_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title 'Incident Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
            $layout['alerts'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alerts' -Title 'Alert List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
            $layout['alert_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
            $layout['action_status'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Preparing authentication...' -Expand)) | Out-Null
            $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (& $getHelpPanelContent) -Expand)) | Out-Null
                $LiveContext.Refresh()

                $authAttempted = $true
            $layout['incidents'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Authenticating with Microsoft Graph...' -Expand)) | Out-Null
            $layout['incident_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title 'Incident Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Authenticating with Microsoft Graph...' -Expand)) | Out-Null
            $layout['action_status'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Authenticating with Microsoft Graph...' -Expand)) | Out-Null
            $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (& $getHelpPanelContent) -Expand)) | Out-Null
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
                $layout['header'].Update((& $getHeaderPanel)) | Out-Null
                $layout['incidents'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Press Ctrl+Q to exit.' -Expand)) | Out-Null
                $layout['incident_details'].Update((Format-SpectrePanel -Header '[red]Authentication Failed[/]' -Data $fatalErrorMessage -Expand)) | Out-Null
                $layout['alerts'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alerts' -Title 'Alert List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No data available.' -Expand)) | Out-Null
                $layout['alert_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No data available.' -Expand)) | Out-Null
                $layout['action_status'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No actions available.' -Expand)) | Out-Null
                $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (& $getHelpPanelContent) -Expand)) | Out-Null
                $LiveContext.Refresh()

                $keyOnError = Get-XdrLastKeyPressed
                if ($keyOnError -and $keyOnError.Key -eq 'Escape') {
                    return
                }

                Start-Sleep -Milliseconds $context.Ui.RefreshIntervalMs
                continue
            }

            if (-not $dataLoaded) {
                $layout['header'].Update((& $getHeaderPanel)) | Out-Null
                $layout['incidents'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Loading incidents...' -Expand)) | Out-Null
                $layout['incident_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title 'Incident Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Loading incidents...' -Expand)) | Out-Null
                $layout['action_status'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'Loading capabilities...' -Expand)) | Out-Null
                $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (& $getHelpPanelContent) -Expand)) | Out-Null
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
                }

                . $enqueueAlertPreloads -Incidents $context.Data.Incidents
                . $startQueuedAlertPreloads
                continue
            }

            . $processAlertLoadJobs
            . $startQueuedAlertPreloads

            if ($null -ne $pendingIncidentResolution) {
                $activePanel = 'action_status'
                $activePanelIndex = [array]::IndexOf($panelOrder, 'action_status')
                $context.Selection.Panel = $activePanel
            }

            $key = Get-XdrLastKeyPressed
            if ($key -ne $null) {
                $keyChar = ([string]$key.KeyChar).ToLowerInvariant()
                $isShiftPressed = (($key.Modifiers -band [ConsoleModifiers]::Shift) -ne 0)
                $isCtrlPressed = (($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0)
                $isAltPressed = (($key.Modifiers -band [ConsoleModifiers]::Alt) -ne 0)

                if ($null -ne $pendingIncidentResolution) {
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
                        Set-LiveStatusMessage -Message 'Incident resolution canceled.' -Level 'warning'
                    }
                    else {
                        if ($key.Key -eq 'PageDown') {
                            if ($pendingIncidentResolution.Step -eq 'determination') {
                                $pendingIncidentResolution.Step = 'comment'
                            }
                            elseif ($pendingIncidentResolution.Step -eq 'comment') {
                                $pendingIncidentResolution.Step = 'confirm'
                            }
                        }
                        elseif ($key.Key -eq 'PageUp') {
                            if ($pendingIncidentResolution.Step -eq 'confirm') {
                                $pendingIncidentResolution.Step = 'comment'
                            }
                            elseif ($pendingIncidentResolution.Step -eq 'comment') {
                                $pendingIncidentResolution.Step = 'determination'
                            }
                        }

                        switch ([string]$pendingIncidentResolution.Step) {
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
                                    $selectedDeterminationOption = $pendingIncidentResolution.DeterminationOptions[$pendingIncidentResolution.DeterminationIndex]
                                    $selectedDeterminationLabel = [string]$selectedDeterminationOption.label
                                        $commentText = if ([string]::IsNullOrWhiteSpace([string]$pendingIncidentResolution.ResolvingComment)) { $null } else { [string]$pendingIncidentResolution.ResolvingComment }

                                    $resolveResult = Set-XdrIncidentTriage -Context $context -IncidentId $selectedIncident.IncidentId -Status 'Resolved' -Determination $selectedDeterminationLabel -Comment $commentText -SkipConfirmation
                                    Set-StatusFromResult -Result $resolveResult
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
                                }
                            }
                        }
                    }
                }
                elseif ($null -ne $pendingTextInput) {
                    if ($key.Key -eq 'Escape') {
                        $pendingTextInput = $null
                        Set-LiveStatusMessage -Message 'Comment entry canceled.' -Level 'warning'
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
                    if (-not $isAltPressed -and -not $isCtrlPressed -and $keyChar -eq 'y') {
                        $confirmedResult = & $pendingConfirmation.Execute
                        Set-StatusFromResult -Result $confirmedResult
                        $pendingConfirmation = $null
                    }
                    elseif ((-not $isAltPressed -and -not $isCtrlPressed -and $keyChar -eq 'n') -or $key.Key -eq 'Escape') {
                        $pendingConfirmation = $null
                        Set-LiveStatusMessage -Message 'Action canceled.' -Level 'warning'
                    }
                }
                elseif ($isCtrlPressed -and ($key.Key -eq 'Q' -or $keyChar -eq 'q')) {
                    return
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
                    $selectedIndex = 0
                    $selectedAlertIndex = 0
                    $selectedIncident = $null
                    $selectedAlert = $null
                    $context.Selection.Incident = $null
                    $context.Selection.Alert = $null
                    $alertsByIncidentId.Clear()
                    $selectedAlertIdByIncidentId.Clear()
                    foreach ($jobEntry in @($alertLoadJobsByIncidentId.GetEnumerator())) {
                        Stop-Job -Job $jobEntry.Value -ErrorAction SilentlyContinue | Out-Null
                        Remove-Job -Job $jobEntry.Value -Force -ErrorAction SilentlyContinue
                    }
                    $alertLoadJobsByIncidentId.Clear()
                    $alertPreloadQueue.Clear()
                    Set-LiveStatusMessage -Message 'Refreshing incidents and alert cache...' -Level 'info'
                    continue
                }

                if (-not $selectedIncident) {
                    continue
                }

                if ($key.Key -eq 'DownArrow' -and $activePanel -eq 'incidents') {
                    $selectedIndex = ($selectedIndex + 1) % $context.Data.Incidents.Count
                    $selectedIncident = $context.Data.Incidents[$selectedIndex]
                    $context.Selection.Incident = $selectedIncident
                    $incidentId = [string]$selectedIncident.IncidentId
                    if (-not (. $restoreCachedAlertsForIncident $incidentId)) {
                        $selectedAlert = $null
                        $selectedAlertIndex = 0
                        $context.Selection.Alert = $null
                        $context.Data.Alerts = @()
                        . $startAlertLoadJob -Incident $selectedIncident | Out-Null
                    }
                }
                elseif ($key.Key -eq 'UpArrow' -and $activePanel -eq 'incidents') {
                    $selectedIndex = ($selectedIndex - 1 + $context.Data.Incidents.Count) % $context.Data.Incidents.Count
                    $selectedIncident = $context.Data.Incidents[$selectedIndex]
                    $context.Selection.Incident = $selectedIncident
                    $incidentId = [string]$selectedIncident.IncidentId
                    if (-not (. $restoreCachedAlertsForIncident $incidentId)) {
                        $selectedAlert = $null
                        $selectedAlertIndex = 0
                        $context.Selection.Alert = $null
                        $context.Data.Alerts = @()
                        . $startAlertLoadJob -Incident $selectedIncident | Out-Null
                    }
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
                elseif ($key.Key -eq 'DownArrow' -and $activePanel -eq 'action_status' -and $actionEntries.Count -gt 0) {
                    $selectedActionIndex = ($selectedActionIndex + 1) % $actionEntries.Count
                }
                elseif ($key.Key -eq 'UpArrow' -and $activePanel -eq 'action_status' -and $actionEntries.Count -gt 0) {
                    $selectedActionIndex = ($selectedActionIndex - 1 + $actionEntries.Count) % $actionEntries.Count
                }
                elseif ($key.Key -eq 'Enter' -and $activePanel -in @('incidents', 'incident_details')) {
                    if ($selectedIncident) {
                        $incidentId = [string]$selectedIncident.IncidentId
                        if (-not (. $restoreCachedAlertsForIncident $incidentId)) {
                            if (. $startAlertLoadJob -Incident $selectedIncident) {
                                Set-LiveStatusMessage -Message 'Loading alerts in background...' -Level 'info'
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
                        . $invokeActionShortcut $selectedAction.Shortcut
                    }
                    else {
                        Set-LiveStatusMessage -Message "$($selectedAction.Label) is not available right now." -Level 'warning'
                    }
                }
                elseif ($isAltPressed -and $keyChar -in @('a', 'u', 'o', 'i', 'r', 'c', 'l', 'n', 'p', 'm')) {
                    . $invokeActionShortcut $keyChar
                }
            }

            if (-not $context.Data.Incidents) {
                $layout['header'].Update((& $getHeaderPanel)) | Out-Null
                $layout['incidents'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No incidents found. Press Ctrl+Q to exit.' -Expand)) | Out-Null
                $layout['incident_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title 'Incident Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No incident selected.' -Expand)) | Out-Null
                $layout['alerts'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alerts' -Title 'Alert List' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No incident selected.' -Expand)) | Out-Null
                $layout['alert_details'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No alert selected.' -Expand)) | Out-Null
                $layout['action_status'].Update((Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No incident selected.' -Expand)) | Out-Null
                $layout['help'].Update((Format-SpectrePanel -Header "[white]Help | $((Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation) -join ' | ')[/]" -Data (& $getHelpPanelContent) -Expand)) | Out-Null
                $LiveContext.Refresh()
                Start-Sleep -Milliseconds $context.Ui.RefreshIntervalMs
                continue
            }

            $incidentLines = $context.Data.Incidents | ForEach-Object {
                if ($_.IncidentId -eq $selectedIncident.IncidentId) {
                    "[bold $($context.Ui.ThemeColor)]$(Get-SpectreEscapedText $_.DisplayName)[/]"
                }
                elseif ([string]$_.Status -ieq 'resolved') {
                    "[lightgreen]$(Get-SpectreEscapedText $_.DisplayName)[/]"
                }
                else {
                    Get-SpectreEscapedText $_.DisplayName
                }
            }

            $incidentPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incidents' -Title "Incident List ($($context.Data.Incidents.Count))" -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data (($incidentLines | Out-String)) -Color (Get-PanelBorderColor -PanelName 'incidents' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Expand

            $incidentDetails = [pscustomobject]@{
                IncidentId    = $selectedIncident.IncidentId
                DisplayName   = $selectedIncident.DisplayName
                Status        = $selectedIncident.Status
                Determination = $selectedIncident.Determination
                AssignedTo    = $selectedIncident.AssignedTo
                Severity      = $selectedIncident.Severity
                AlertCount    = $selectedIncident.AlertCount
                IncidentWebUrl = $selectedIncident.IncidentWebUrl
                PanelFocus    = $activePanel
                Created       = $selectedIncident.CreatedDateTime
            } | Format-SpectreJson | Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'incident_details' -Title 'Incident Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Color (Get-PanelBorderColor -PanelName 'incident_details' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Expand

            $alertLines = if ($context.Data.Alerts) {
                $context.Data.Alerts | ForEach-Object {
                    if ($selectedAlert -and $_.AlertId -eq $selectedAlert.AlertId) {
                        "[bold $($context.Ui.ThemeColor)]$(Get-SpectreEscapedText $_.Title)[/]"
                    }
                    else {
                        Get-SpectreEscapedText $_.Title
                    }
                }
            }
            else {
                @('Press Enter on an incident to load alerts.')
            }

            $alertsPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alerts' -Title "Alert List ($($context.Data.Alerts.Count))" -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data (($alertLines | Out-String)) -Color (Get-PanelBorderColor -PanelName 'alerts' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Expand

            $alertDetails = if ($selectedAlert) {
                [pscustomobject]@{
                    AlertId     = $selectedAlert.AlertId
                    Title       = $selectedAlert.Title
                    Status      = $selectedAlert.Status
                    Severity    = $selectedAlert.Severity
                    PanelFocus  = $activePanel
                    Created     = $selectedAlert.CreatedDateTime
                    AlertWebUrl = $selectedAlert.AlertWebUrl
                } | Format-SpectreJson | Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Color (Get-PanelBorderColor -PanelName 'alert_details' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Expand
            }
            else {
                Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'alert_details' -Title 'Alert Details' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data 'No alert selected.' -Color (Get-PanelBorderColor -PanelName 'alert_details' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Expand
            }

            $incidentActionLines = @()
            $actionEntries = @()
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
            $incidentCommentReasons = @()
            $incidentActionLines += (New-ActionStateLine -Label '(Alt+C) Add comment to selected incident' -Reasons $incidentCommentReasons)
            $actionEntries += [pscustomobject]@{ Shortcut = 'c'; Label = 'Add comment to selected incident'; IsEnabled = $true; Reasons = $incidentCommentReasons }
            $incidentActionLines += '(Alt+L) Load alerts for selected incident'
            $actionEntries += [pscustomobject]@{ Shortcut = 'l'; Label = 'Load alerts for selected incident'; IsEnabled = $true; Reasons = @() }

            $actionLines = @($incidentActionLines)
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
                $step1Heading = if ($pendingIncidentResolution.Step -eq 'determination') {
                    "[bold $($context.Ui.ThemeColor)]Step 1/3: Determination (ACTIVE)[/]"
                }
                else {
                    '[bold grey]Step 1/3: Determination[/]'
                }
                $step2Heading = if ($pendingIncidentResolution.Step -eq 'comment') {
                    "[bold $($context.Ui.ThemeColor)]Step 2/3: Resolving comment (ACTIVE)[/]"
                }
                else {
                    '[bold grey]Step 2/3: Resolving comment[/]'
                }
                $step3Heading = if ($pendingIncidentResolution.Step -eq 'confirm') {
                    "[bold $($context.Ui.ThemeColor)]Step 3/3: Final confirmation (ACTIVE)[/]"
                }
                else {
                    '[bold grey]Step 3/3: Final confirmation[/]'
                }

                $resolutionLines = @()
                $resolutionLines += $step1Heading
                foreach ($idx in 0..([Math]::Max(0, @($pendingIncidentResolution.DeterminationOptions).Count - 1))) {
                    if (@($pendingIncidentResolution.DeterminationOptions).Count -eq 0) {
                        break
                    }

                    $option = $pendingIncidentResolution.DeterminationOptions[$idx]
                    $label = Get-SpectreEscapedText ([string]$option.label)
                    $prefix = if ($pendingIncidentResolution.Step -eq 'determination' -and $pendingIncidentResolution.DeterminationIndex -eq $idx) { "[bold $($context.Ui.ThemeColor)]>[/]" } else { ' ' }
                    $color = if ($pendingIncidentResolution.DeterminationIndex -eq $idx) { $context.Ui.ThemeColor } else { 'white' }
                    $resolutionLines += "$prefix [bold $color]$label[/]"
                }

                $resolutionLines += ''
                $resolutionLines += $step2Heading
                $commentValue = [string]$pendingIncidentResolution.ResolvingComment
                if ([string]::IsNullOrWhiteSpace($commentValue)) {
                    $resolutionLines += '[grey]<empty - default comment will be used>[/]'
                }
                else {
                    $resolutionLines += "[white]$(Get-SpectreEscapedText $commentValue)[/]"
                }

                $selectedDeterminationOption = $pendingIncidentResolution.DeterminationOptions[[int]$pendingIncidentResolution.DeterminationIndex]
                $selectedDeterminationLabel = Get-SpectreEscapedText ([string]$selectedDeterminationOption.label)
                $resolutionLines += ''
                $resolutionLines += $step3Heading
                $resolutionLines += "[white]Determination:[/] [bold]$selectedDeterminationLabel[/]"
                $resolutionLines += "[white]Ready to resolve this incident.[/]"
                $resolutionLines += '[grey]Enter/Y confirm | N back | Esc cancel[/]'

                $actionStatusPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Incident Resolution' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($resolutionLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'action_status' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Expand
            }
            else {
                $actionStatusPanel = Format-SpectrePanel -Header (Get-PanelHeaderMarkup -PanelName 'action_status' -Title 'Action Status' -ActivePanel $activePanel -Color $context.Ui.ThemeColor) -Data ($actionDisplayLines -join "`n") -Color (Get-PanelBorderColor -PanelName 'action_status' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Expand
            }

            $contextHelpLine = (Get-ContextAwareHelpLines -ActivePanel $activePanel -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -PendingConfirmation $pendingConfirmation -PendingTextInput $pendingTextInput -PendingIncidentResolution $pendingIncidentResolution) -join ' | '
            $helpHeaderText = "Help | $contextHelpLine"
            $helpPanel = Format-SpectrePanel -Header "[white]$helpHeaderText[/]" -Data (& $getHelpPanelContent) -Color (Get-PanelBorderColor -PanelName 'help' -ActivePanel $activePanel -AccentColor $context.Ui.ThemeColor) -Expand

            $layout['header'].Update((& $getHeaderPanel)) | Out-Null
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