function Get-XdrLiveHelpPanelContent {
    <#
    .SYNOPSIS
    Builds help panel content for current live dashboard state.

    .DESCRIPTION
    Renders contextual status/help content, including input mode, confirmation
    prompts, and prefetch indicator messaging.

    .PARAMETER Context
    Runtime context object.

    .PARAMETER SelectedIncident
    Currently selected incident used to derive alert cache state.

    .PARAMETER PendingIncidentResolution
    Current incident resolution workflow payload.

    .PARAMETER PendingTextInput
    Current text input payload.

    .PARAMETER PendingConfirmation
    Current confirmation payload.

    .PARAMETER AlertsByIncidentId
    Alert cache map keyed by incident id.

    .PARAMETER AlertLoadJobsByIncidentId
    Running jobs map keyed by incident id.

    .PARAMETER AlertPreloadQueue
    Incident preload queue.

    .PARAMETER PrefetchCompletedAt
    Timestamp reference for completed prefetch.

    .PARAMETER LastRefreshAt
    Timestamp for last incident refresh.

    .PARAMETER ShowKeyboardHelpOverlay
    Renders the full keyboard shortcut overlay when enabled.

    .OUTPUTS
    System.String

    .EXAMPLE
    Get-XdrLiveHelpPanelContent -Context $context -AlertsByIncidentId $cache -AlertLoadJobsByIncidentId $jobs -AlertPreloadQueue $queue -PrefetchCompletedAt ([ref]$prefetchCompletedAt)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter()]
        [object]$SelectedIncident,

        [Parameter()]
        [object]$PendingIncidentResolution,

        [Parameter()]
        [object]$PendingTextInput,

        [Parameter()]
        [object]$PendingConfirmation,

        [Parameter(Mandatory)]
        [hashtable]$AlertsByIncidentId,

        [Parameter(Mandatory)]
        [hashtable]$AlertLoadJobsByIncidentId,

        [Parameter(Mandatory)]
        [System.Collections.Queue]$AlertPreloadQueue,

        [Parameter(Mandatory)]
        [ref]$PrefetchCompletedAt,

        [Parameter()]
        [Nullable[datetime]]$LastRefreshAt = $null,

        [Parameter()]
        [Nullable[datetime]]$HeartbeatAt = $null,

        [Parameter()]
        [int]$HeartbeatCounter = 0,

        [Parameter()]
        [switch]$IsQueryMode,

        [Parameter()]
        [switch]$ShowKeyboardHelpOverlay
    )

    $lastRefreshText = if ($null -ne $LastRefreshAt -and $LastRefreshAt -ne [datetime]::MinValue) {
        "Last refresh: $([string](Get-SpectreEscapedText ($LastRefreshAt.ToString('yyyy-MM-dd HH:mm:ss'))))"
    }
    else {
        'Last refresh: not yet'
    }
    $lastRefreshLine = "[grey]$lastRefreshText[/]"

    # Heartbeat indicator - shows dashboard is responsive
    $heartbeatText = if ($null -ne $HeartbeatAt) {
        $secondsSinceHeartbeat = [int]((Get-Date) - $HeartbeatAt).TotalSeconds
        $spinner = @('-', '\', '|', '/')[$HeartbeatCounter % 4]
        "Heartbeat: ${secondsSinceHeartbeat}s ago ${spinner}"
    }
    else {
        'Heartbeat: initializing...'
    }
    $heartbeatLine = "[cyan]$(Get-SpectreEscapedText $heartbeatText)[/]"
    $shortcutHintLine = if ($IsQueryMode.IsPresent) {
        '[grey]Hint: Alt+H Hunting mode off | Alt+X Execute query | Ctrl+Alt+K Input debug | F1 Help | Tab/Shift+Tab Switch | q Quit[/]'
    }
    else {
        '[grey]Hint: F1 Help | F5/r Refresh | Tab/Shift+Tab Switch | q Quit[/]'
    }

    $getLogicalPanelName = {
        param(
            [string]$PanelName,
            [bool]$QueryMode
        )

        switch ($PanelName) {
            'incident_list' { return 'incidents' }
            'incident_details' { return 'incident details' }
            'alert_list' { return 'alerts' }
            'alert_details' { return 'alert details' }
            'incident_actions' { return 'incident actions' }
            'query_catalog' { return 'query catalog' }
            'query_preview' { return 'query preview' }
            'query_activity' { return 'query activity' }
            'query_results' { return 'query results' }
            'query_actions' { return 'query actions' }
            default { return $PanelName }
        }
    }

    $inputDebugLines = @()
    if ($Context.PSObject.Properties.Name -contains 'Diagnostics' -and $Context.Diagnostics -and $Context.Diagnostics.PSObject.Properties.Name -contains 'InputDebugEnabled' -and $Context.Diagnostics.InputDebugEnabled) {
        $inputDebugLines += '[bold black on grey70] Input Debug [/]'

        $lastInput = $Context.Diagnostics.LastInput
        if ($lastInput) {
            $keyCharText = if ([string]::IsNullOrWhiteSpace([string]$lastInput.KeyChar)) { '<none>' } else { [string]$lastInput.KeyChar }
            $logicalPanelName = [string](& $getLogicalPanelName ([string]$lastInput.ActivePanel) ([bool]$lastInput.IsQueryMode))
            $inputDebugLines += "[grey]Last key: $([string](Get-SpectreEscapedText ([string]$lastInput.Key))) | Char: $([string](Get-SpectreEscapedText $keyCharText)) | Modifiers: $([string](Get-SpectreEscapedText ([string]$lastInput.Modifiers)))[/]"
            $inputDebugLines += "[grey]Panel: $([string](Get-SpectreEscapedText $logicalPanelName)) | Query mode: $([string](Get-SpectreEscapedText ([string]$lastInput.IsQueryMode))) | Query index: $([string](Get-SpectreEscapedText ([string]$lastInput.SelectedQueryIndex)))[/]"
            if (-not [string]::IsNullOrWhiteSpace([string]$lastInput.SelectedQueryId)) {
                $inputDebugLines += "[grey]Query: $([string](Get-SpectreEscapedText ([string]$lastInput.SelectedQueryId)))[/]"
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$lastInput.SelectedEntity)) {
                $inputDebugLines += "[grey]Entity: $([string](Get-SpectreEscapedText ([string]$lastInput.SelectedEntity)))[/]"
            }
        }
        else {
            $inputDebugLines += '[grey]No key input captured yet.[/]'
        }
    }

    $selectedIncidentId = if ($SelectedIncident) { [string]$SelectedIncident.IncidentId } else { $null }
    $cacheStateLine = if ([string]::IsNullOrWhiteSpace($selectedIncidentId)) {
        '[grey]Alert cache: no incident selected[/]'
    }
    elseif ($AlertLoadJobsByIncidentId.ContainsKey($selectedIncidentId)) {
        '[deepskyblue1]Alert cache: loading[/]'
    }
    elseif ($AlertsByIncidentId.ContainsKey($selectedIncidentId)) {
        $cachedAlertCount = @($AlertsByIncidentId[$selectedIncidentId]).Count
        $alertLabel = if ($cachedAlertCount -eq 1) { 'alert' } else { 'alerts' }
        "[green]Alert cache: warm ($cachedAlertCount $alertLabel)[/]"
    }
    else {
        '[yellow]Alert cache: cold[/]'
    }

    if ($null -ne $PendingIncidentResolution) {
        return "$lastRefreshLine`n$heartbeatLine`n$cacheStateLine"
    }

    if ($null -ne $PendingTextInput) {
        $title = if ([string]::IsNullOrWhiteSpace([string]$PendingTextInput.Title)) {
            'COMMENT'
        }
        else {
            Get-SpectreEscapedText ([string]$PendingTextInput.Title)
        }

        $prompt = Get-SpectreEscapedText ([string]$PendingTextInput.Prompt)
        $inputValue = if ([string]::IsNullOrWhiteSpace([string]$PendingTextInput.Value)) { '' } else { Get-SpectreEscapedText ([string]$PendingTextInput.Value) }
        $inputDisplay = if ([string]::IsNullOrWhiteSpace($inputValue)) { '[grey]<empty>[/]' } else { "[white]$inputValue[/]" }
        return "[bold black on orange1] $title [/] [yellow]$prompt[/]`n$inputDisplay [grey](Enter submit | Esc cancel)[/]`n$lastRefreshLine`n$heartbeatLine`n$cacheStateLine"
    }

    $prefetchRaw = [string](Get-XdrLiveAlertPrefetchIndicator -Context $Context -AlertsByIncidentId $AlertsByIncidentId -AlertLoadJobsByIncidentId $AlertLoadJobsByIncidentId -AlertPreloadQueue $AlertPreloadQueue -PrefetchCompletedAt $PrefetchCompletedAt)
    $hasPrefetchLine = -not [string]::IsNullOrWhiteSpace($prefetchRaw)
    $prefetchLine = if ($hasPrefetchLine) { Get-SpectreEscapedText $prefetchRaw } else { $null }
    $statusText = [string]$Context.Ui.StatusMessage

    if ($null -ne $PendingConfirmation) {
        $statusLine = if ([string]::IsNullOrWhiteSpace($statusText)) {
            '[bold yellow]WARN Confirmation required[/]'
        }
        else {
            "[bold yellow]$(Get-SpectreEscapedText $statusText)[/]"
        }

        $promptText = Get-SpectreEscapedText ([string]$PendingConfirmation.Prompt)
        $confirmLine = "[bold black on yellow] CONFIRM [/] [yellow]$promptText[/] [grey]Y confirm | N or Esc cancel[/]"
        return "$statusLine`n$confirmLine`n$lastRefreshLine`n$heartbeatLine`n$cacheStateLine"
    }

    if ($ShowKeyboardHelpOverlay.IsPresent) {
        $overlayLines = @(
            '[bold black on deepskyblue1] Keyboard Shortcuts [/]',
            '[white]F1[/] toggle keyboard help overlay',
            '[white]F5[/] or [white]r[/] refresh incidents and alert cache',
            '[white]Tab[/] / [white]Shift+Tab[/] or [white]PgUp/PgDn[/] switch active panel',
            '[white]Up/Down[/] move selection in the active list',
            '[white]Enter[/] load alerts, confirm, run selected action, or execute selected hunting query',
            '[white]Ctrl+Alt+K[/] toggle input debug overlay details',
            '[white]Alt+Shift+L[/] force reload selected incident alerts',
            '[white]Alt+H[/] toggle hunting mode | [white]Enter[/]/[white]Alt+X[/] execute selected query in hunting mode',
            '[white]Alt+A/U/O/I/R/K/C/L[/] incident actions',
            '[white]Alt+N/P/M[/] alert status actions',
            '[white]Alt+E[/] entities view | [white]Alt+D[/] incident details view',
            '[white]q[/] or [white]Ctrl+Q[/] quit dashboard (requires confirmation)',
            '[white]Esc[/] cancel current dialog | [white]Ctrl+C[/] force exit',
            $lastRefreshLine,
            $heartbeatLine,
            $cacheStateLine
        )

        return ($overlayLines -join "`n")
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
                return ((@("[bold $statusColor]$statusCode $statusMessageText[/]", "[grey]$prefetchLine[/]") + $inputDebugLines + @($lastRefreshLine, $heartbeatLine, $cacheStateLine, $shortcutHintLine)) -join "`n")
            }

            return ((@("[bold $statusColor]$statusCode $statusMessageText[/]") + $inputDebugLines + @($lastRefreshLine, $heartbeatLine, $cacheStateLine, $shortcutHintLine)) -join "`n")
        }

        if ($hasPrefetchLine) {
            return ((@("[white]$(Get-SpectreEscapedText $statusText)[/]", "[grey]$prefetchLine[/]") + $inputDebugLines + @($lastRefreshLine, $heartbeatLine, $cacheStateLine, $shortcutHintLine)) -join "`n")
        }

        return ((@("[white]$(Get-SpectreEscapedText $statusText)[/]") + $inputDebugLines + @($lastRefreshLine, $heartbeatLine, $cacheStateLine, $shortcutHintLine)) -join "`n")
    }

    if ($hasPrefetchLine) {
        return ((@("[grey]$prefetchLine[/]") + $inputDebugLines + @($lastRefreshLine, $heartbeatLine, $cacheStateLine, $shortcutHintLine)) -join "`n")
    }

    return (($inputDebugLines + @($lastRefreshLine, $heartbeatLine, $cacheStateLine, $shortcutHintLine)) -join "`n")
}
