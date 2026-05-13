function Set-LiveStatusMessage {
    <#
    .SYNOPSIS
    Updates dashboard status message metadata.

    .DESCRIPTION
    Prefixes a status message with a standard level code and updates the
    timestamp of the latest notification in the runtime context.

    .PARAMETER Context
    Runtime context object.

    .PARAMETER Message
    Message text to publish.

    .PARAMETER Level
    Status level used to set the message prefix.

    .PARAMETER Persistent
    Keeps the status visible until another message replaces it.

    .PARAMETER DurationSeconds
    Lifespan for transient info/success messages.

    .OUTPUTS
    None

    .EXAMPLE
    Set-LiveStatusMessage -Context $context -Message 'Loaded incidents' -Level success
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('info', 'success', 'warning', 'error')]
        [string]$Level = 'info',

        [Parameter()]
        [switch]$Persistent,

        [Parameter()]
        [ValidateRange(1, 60)]
        [int]$DurationSeconds = 3
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

    $Context.Ui.StatusMessage = "$prefix $Message"
    $Context.Ui.LastNotification = Get-Date

    if (-not $Context.Ui.PSObject.Properties['StatusLevel']) {
        Add-Member -InputObject $Context.Ui -MemberType NoteProperty -Name 'StatusLevel' -Value $null -Force
    }

    if (-not $Context.Ui.PSObject.Properties['StatusExpiresAt']) {
        Add-Member -InputObject $Context.Ui -MemberType NoteProperty -Name 'StatusExpiresAt' -Value $null -Force
    }

    $Context.Ui.StatusLevel = $Level

    $isPersistentLevel = $Level -in @('warning', 'error')
    if ($Persistent.IsPresent -or $isPersistentLevel) {
        $Context.Ui.StatusExpiresAt = $null
    }
    else {
        $Context.Ui.StatusExpiresAt = (Get-Date).AddSeconds($DurationSeconds)
    }
}
