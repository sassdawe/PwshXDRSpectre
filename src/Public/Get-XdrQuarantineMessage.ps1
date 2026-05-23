function Get-XdrQuarantineMessage {
    <#
        .SYNOPSIS
        Retrieves Microsoft Defender for Office 365 quarantine messages.

        .DESCRIPTION
        Uses the Exchange Online PowerShell quarantine API surface exposed by
        Get-QuarantineMessage to retrieve quarantined email messages and convert
        them into compact view models for analyst review.

        .PARAMETER Identity
        Optional quarantine message identity to retrieve.

        .PARAMETER SenderAddress
        Optional sender address filter passed to Get-QuarantineMessage.

        .PARAMETER RecipientAddress
        Optional recipient address filter passed to Get-QuarantineMessage.

        .PARAMETER StartReceivedDate
        Optional start date filter for received messages.

        .PARAMETER EndReceivedDate
        Optional end date filter for received messages.

        .PARAMETER Limit
        Maximum number of quarantine messages to return. Defaults to 50.

        .OUTPUTS
        PSCustomObject quarantine message view models.

        .EXAMPLE
        Get-XdrQuarantineMessage -Limit 25

        .EXAMPLE
        Get-XdrQuarantineMessage -RecipientAddress user@contoso.com

        .NOTES
        Requires ExchangeOnlineManagement to be installed, imported, and connected
        with Connect-ExchangeOnline. Microsoft Graph Security APIs do not currently
        expose equivalent quarantine release/delete operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Identity,

        [Parameter()]
        [string]$SenderAddress,

        [Parameter()]
        [string]$RecipientAddress,

        [Parameter()]
        [datetime]$StartReceivedDate,

        [Parameter()]
        [datetime]$EndReceivedDate,

        [Parameter()]
        [ValidateRange(1, 5000)]
        [int]$Limit = 50
    )

    if (-not (Get-Command -Name Get-QuarantineMessage -ErrorAction SilentlyContinue)) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new('Get-QuarantineMessage was not found. Install/import ExchangeOnlineManagement and connect with Connect-ExchangeOnline before using quarantine features.'),
            'QuarantineCommandNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            'Get-QuarantineMessage'
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $parameters = @{}
    foreach ($parameterName in @('Identity', 'SenderAddress', 'RecipientAddress', 'StartReceivedDate', 'EndReceivedDate')) {
        if ($PSBoundParameters.ContainsKey($parameterName)) {
            $parameters[$parameterName] = $PSBoundParameters[$parameterName]
        }
    }

    @(Get-QuarantineMessage @parameters) |
        Select-Object -First $Limit |
        ConvertTo-XdrQuarantineMessageViewModel
}
