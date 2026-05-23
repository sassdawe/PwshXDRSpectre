function Invoke-XdrQuarantineAction {
    <#
        .SYNOPSIS
        Releases or deletes a quarantined email message.

        .DESCRIPTION
        Invokes the Exchange Online PowerShell quarantine action cmdlets for a
        selected Microsoft Defender for Office 365 quarantine message. Release
        requires an explicit release target via ReleaseToAll or RecipientAddress.

        .PARAMETER Identity
        The quarantine message identity to act on.

        .PARAMETER Action
        The quarantine action to perform: Release or Delete.

        .PARAMETER RecipientAddress
        One or more recipients to release the message to when Action is Release.

        .PARAMETER ReleaseToAll
        Releases the message to all original recipients when Action is Release.

        .PARAMETER PassThru
        Returns the underlying Exchange Online action result.

        .OUTPUTS
        No output by default. With PassThru, returns the underlying action result.

        .EXAMPLE
        Invoke-XdrQuarantineAction -Identity '<quarantine-id>' -Action Release -ReleaseToAll -Confirm:$false

        .EXAMPLE
        Invoke-XdrQuarantineAction -Identity '<quarantine-id>' -Action Delete -Confirm:$false

        .NOTES
        Requires ExchangeOnlineManagement to be installed, imported, and connected
        with Connect-ExchangeOnline.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Identity,

        [Parameter(Mandatory)]
        [ValidateSet('Release', 'Delete')]
        [string]$Action,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$RecipientAddress,

        [Parameter()]
        [switch]$ReleaseToAll,

        [Parameter()]
        [switch]$PassThru
    )

    process {
        if ($Action -eq 'Release') {
            if (-not $ReleaseToAll.IsPresent -and -not $RecipientAddress) {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new('Specify -ReleaseToAll or -RecipientAddress when releasing a quarantined message.'),
                    'QuarantineReleaseTargetRequired',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $Identity
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            if (-not (Get-Command -Name Release-QuarantineMessage -ErrorAction SilentlyContinue)) {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new('Release-QuarantineMessage was not found. Install/import ExchangeOnlineManagement and connect with Connect-ExchangeOnline before using quarantine features.'),
                    'QuarantineCommandNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    'Release-QuarantineMessage'
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            if ($PSCmdlet.ShouldProcess($Identity, 'Release quarantined message')) {
                $parameters = @{ Identity = $Identity }
                if ($ReleaseToAll.IsPresent) {
                    $parameters.ReleaseToAll = $true
                }
                if ($RecipientAddress) {
                    $parameters.RecipientAddress = $RecipientAddress
                }

                $result = Release-QuarantineMessage @parameters
                if ($PassThru.IsPresent) {
                    $result
                }
            }

            return
        }

        if (-not (Get-Command -Name Delete-QuarantineMessage -ErrorAction SilentlyContinue)) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new('Delete-QuarantineMessage was not found. Install/import ExchangeOnlineManagement and connect with Connect-ExchangeOnline before using quarantine features.'),
                'QuarantineCommandNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                'Delete-QuarantineMessage'
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        if ($PSCmdlet.ShouldProcess($Identity, 'Delete quarantined message')) {
            $result = Delete-QuarantineMessage -Identity $Identity
            if ($PassThru.IsPresent) {
                $result
            }
        }
    }
}
