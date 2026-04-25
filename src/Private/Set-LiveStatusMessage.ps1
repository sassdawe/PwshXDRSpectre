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

    $Context.Ui.StatusMessage = "$prefix $Message"
    $Context.Ui.LastNotification = Get-Date
}
