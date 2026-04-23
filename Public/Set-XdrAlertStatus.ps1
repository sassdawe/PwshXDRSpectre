function Set-XdrAlertStatus {
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