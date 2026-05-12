function Get-XdrLiveHelpPanelContent {
    <#
    .SYNOPSIS
    Builds help panel content for current live dashboard state.

    .DESCRIPTION
    Renders contextual status/help content, including input mode, confirmation
    prompts, and prefetch indicator messaging.

    .PARAMETER Context
    Runtime context object.

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
        [ref]$PrefetchCompletedAt

        ,[Parameter()]
        [Nullable[datetime]]$LastRefreshAt = $null

        ,[Parameter()]
        [Nullable[datetime]]$HeartbeatAt = $null

        ,[Parameter()]
        [int]$HeartbeatCounter = 0
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

    if ($null -ne $PendingIncidentResolution) {
        return "$lastRefreshLine`n$heartbeatLine"
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
        return "[bold black on orange1] $title [/] [yellow]$prompt[/]`n$inputDisplay [grey](Enter submit | Esc cancel)[/]`n$lastRefreshLine`n$heartbeatLine"
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
        return "$statusLine`n$confirmLine`n$lastRefreshLine`n$heartbeatLine"
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
                return "[bold $statusColor]$statusCode $statusMessageText[/]`n[grey]$prefetchLine[/]`n$lastRefreshLine`n$heartbeatLine"
            }

            return "[bold $statusColor]$statusCode $statusMessageText[/]`n$lastRefreshLine`n$heartbeatLine"
        }

        if ($hasPrefetchLine) {
            return "[white]$(Get-SpectreEscapedText $statusText)[/]`n[grey]$prefetchLine[/]`n$lastRefreshLine`n$heartbeatLine"
        }

        return "[white]$(Get-SpectreEscapedText $statusText)[/]`n$lastRefreshLine`n$heartbeatLine"
    }

    if ($hasPrefetchLine) {
        return "[grey]$prefetchLine[/]`n$lastRefreshLine`n$heartbeatLine"
    }

    return "$lastRefreshLine`n$heartbeatLine"
}
