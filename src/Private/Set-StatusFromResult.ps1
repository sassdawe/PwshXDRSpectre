function Set-StatusFromResult {
    <#
    .SYNOPSIS
    Maps operation results into dashboard status messages.

    .DESCRIPTION
    Translates operation envelopes into user-facing status levels and messages.
    Confirmation-required outcomes are treated as warnings.

    .PARAMETER Context
    Runtime context object.

    .PARAMETER Result
    Operation result envelope.

    .PARAMETER PendingMessage
    Optional override message when confirmation is required.

    .OUTPUTS
    None

    .EXAMPLE
    Set-StatusFromResult -Context $context -Result $result
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter()]
        [object]$Result,

        [Parameter()]
        [string]$PendingMessage
    )

    if (-not $Result) {
        return
    }

    if ($Result.Data -and $Result.Data.ConfirmationRequired) {
        $message = if ($PendingMessage) { $PendingMessage } else { $Result.Message }
        Set-LiveStatusMessage -Context $Context -Message $message -Level 'warning'
        return
    }

    if ($Result.Success) {
        Set-LiveStatusMessage -Context $Context -Message $Result.Message -Level 'success'
        return
    }

    Set-LiveStatusMessage -Context $Context -Message $Result.Message -Level 'error'
}
