function Set-XdrIncidentAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [string]$IncidentId,

        [Parameter()]
        [string]$AssignedTo
    )

    if (-not (Test-XdrCapability -CapabilityName 'AssignIncident' -Context $Context)) {
        return [pscustomobject]@{
            Success   = $false
            Operation = 'Set-XdrIncidentAssignment'
            Message   = 'Capability not available: AssignIncident'
            Data      = $null
            Error     = [pscustomobject]@{
                Operation   = 'Set-XdrIncidentAssignment'
                SafeMessage = 'Capability not available: AssignIncident'
                Timestamp   = Get-Date
            }
            Metadata  = [ordered]@{
                TenantId   = $Context.Session.TenantId
                DurationMs = 0
                Timestamp  = Get-Date
            }
        }
    }

    $assignmentTarget = if ([string]::IsNullOrWhiteSpace($AssignedTo)) { '' } else { $AssignedTo }
    $operation = if ([string]::IsNullOrWhiteSpace($assignmentTarget)) { 'ClearIncidentAssignment' } else { 'AssignIncident' }
    $successMessage = if ($operation -eq 'AssignIncident') { 'Assigned incident successfully.' } else { 'Cleared incident assignment.' }
    $failureMessage = if ($operation -eq 'AssignIncident') { 'Failed to assign incident.' } else { 'Failed to clear incident assignment.' }

    return Invoke-XdrOperation -Operation $operation -Context $Context -TargetObject $IncidentId -ScriptBlock {
        Update-MgSecurityIncident -IncidentId $IncidentId -BodyParameter @{ assignedTo = $assignmentTarget }
    } -SuccessMessage $successMessage -FailureMessage $failureMessage
}