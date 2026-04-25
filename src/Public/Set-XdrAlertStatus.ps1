function Set-XdrAlertStatus {
    <#
        .SYNOPSIS
        Updates the status of a Microsoft Defender XDR security alert.

        .DESCRIPTION
        Resolves the display-friendly status label to the corresponding Microsoft Graph
        enum value using the active triage policy, checks safety policy confirmation
        requirements, and calls the Graph API to update the alert status.

        .PARAMETER Context
        The runtime context object that holds session, capability, and selection state.

        .PARAMETER AlertId
        The unique identifier of the alert to update.

        .PARAMETER Status
        The human-readable alert status to apply (e.g., 'New', 'In progress', 'Resolved').
        The value is mapped to the Graph API enum through the triage policy.

        .PARAMETER SkipConfirmation
        When specified, bypasses safety policy confirmation prompts and applies the
        status change immediately.

        .PARAMETER Policy
        The triage policy object used for enum mapping and safety checks. Defaults to
        the policy returned by Get-XdrTriagePolicy.

        .OUTPUTS
        PSCustomObject containing Success, Operation, Message, Data, Error, and Metadata
        properties. When confirmation is required and not bypassed, Data.ConfirmationRequired
        will be $true.

        .EXAMPLE
        Set-XdrAlertStatus -Context $ctx -AlertId 'alert-123' -Status 'Resolved' -SkipConfirmation

        .NOTES
        Requires the UpdateAlertStatus capability to be present in the context.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [string]$AlertId,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter()]
        [switch]$SkipConfirmation,

        [Parameter()]
        [object]$Policy = (Get-XdrTriagePolicy)
    )

    if (-not (Test-XdrCapability -CapabilityName 'UpdateAlertStatus' -Context $Context)) {
        return [pscustomobject]@{
            Success   = $false
            Operation = 'Set-XdrAlertStatus'
            Message   = 'Capability not available: UpdateAlertStatus'
            Data      = $null
            Error     = [pscustomobject]@{
                Operation   = 'Set-XdrAlertStatus'
                SafeMessage = 'Capability not available: UpdateAlertStatus'
                Timestamp   = Get-Date
            }
            Metadata  = [ordered]@{
                TenantId   = $Context.Session.TenantId
                DurationMs = 0
                Timestamp  = Get-Date
            }
        }
    }

    $graphStatus = Resolve-XdrGraphEnumValue -MapName 'alertStatusMap' -DisplayValue $Status -Policy $Policy
    $actionName = "Set alert status to $Status"
    if ((Test-XdrActionSafetyPolicy -ActionName $actionName -Policy $Policy) -and -not $SkipConfirmation.IsPresent) {
        return [pscustomobject]@{
            Success   = $false
            Operation = 'Set-XdrAlertStatus'
            Message   = 'Confirmation required before this alert action can run.'
            Data      = [pscustomobject]@{
                ConfirmationRequired = $true
                ActionName           = $actionName
                Prompt               = (Get-XdrActionSafetyPolicy -ActionName $actionName -Policy $Policy).prompt
                BodyParameter        = [pscustomobject]@{ status = $graphStatus }
            }
            Error     = $null
            Metadata  = [ordered]@{
                TenantId   = $Context.Session.TenantId
                DurationMs = 0
                Timestamp  = Get-Date
            }
        }
    }

    $operationResult = Invoke-XdrOperation -Operation 'Set-XdrAlertStatus' -Context $Context -TargetObject $AlertId -ScriptBlock {
        Update-MgSecurityAlertV2 -AlertId $AlertId -BodyParameter @{ status = $graphStatus }
    } -SuccessMessage 'Updated alert status successfully.' -FailureMessage 'Failed to update alert status.'

    if ($operationResult.Success -and $Context.Selection.Alert -and $Context.Selection.Alert.AlertId -eq $AlertId) {
        $Context.Selection.Alert.Status = $graphStatus
    }

    return $operationResult
}