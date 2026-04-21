function Set-XdrIncidentTriage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [string]$IncidentId,

        [Parameter()]
        [string]$Status,

        [Parameter()]
        [string]$Classification,

        [Parameter()]
        [string]$Determination,

        [Parameter()]
        [string]$Comment,

        [Parameter()]
        [string]$AssignedTo,

        [Parameter()]
        [switch]$AssignToMe,

        [Parameter()]
        [switch]$ClearAssignment,

        [Parameter()]
        [switch]$SkipConfirmation,

        [Parameter()]
        [object]$Policy = (Get-XdrTriagePolicy)
    )

    $body = @{}
    $actionNames = @()
    $autoResolvedComment = $false

    if ($AssignToMe.IsPresent) {
        $assignedIdentity = Get-XdrAssignTargetIdentity -Context $Context
        if ([string]::IsNullOrWhiteSpace($assignedIdentity)) {
            return [pscustomobject]@{
                Success   = $false
                Operation = 'Set-XdrIncidentTriage'
                Message   = 'Unable to resolve analyst identity for assignment.'
                Data      = $null
                Error     = [pscustomobject]@{
                    Operation   = 'Set-XdrIncidentTriage'
                    SafeMessage = 'Unable to resolve analyst identity for assignment.'
                    Timestamp   = Get-Date
                }
                Metadata  = [ordered]@{
                    TenantId   = $Context.Session.TenantId
                    DurationMs = 0
                    Timestamp  = Get-Date
                }
            }
        }

        $AssignedTo = $assignedIdentity
        $actionNames += 'Assign incident to me'
    }

    if ($ClearAssignment.IsPresent) {
        $AssignedTo = ''
        $actionNames += 'Clear incident assignment'
    }

    if (-not [string]::IsNullOrWhiteSpace($AssignedTo)) {
        if (-not (Test-XdrCapability -CapabilityName 'AssignIncident' -Context $Context)) {
            return [pscustomobject]@{
                Success   = $false
                Operation = 'Set-XdrIncidentTriage'
                Message   = 'Capability not available: AssignIncident'
                Data      = $null
                Error     = [pscustomobject]@{
                    Operation   = 'Set-XdrIncidentTriage'
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

        $body.assignedTo = $AssignedTo
    }
    elseif ($ClearAssignment.IsPresent) {
        if (-not (Test-XdrCapability -CapabilityName 'ClearIncidentAssignment' -Context $Context)) {
            return [pscustomobject]@{
                Success   = $false
                Operation = 'Set-XdrIncidentTriage'
                Message   = 'Capability not available: ClearIncidentAssignment'
                Data      = $null
                Error     = [pscustomobject]@{
                    Operation   = 'Set-XdrIncidentTriage'
                    SafeMessage = 'Capability not available: ClearIncidentAssignment'
                    Timestamp   = Get-Date
                }
                Metadata  = [ordered]@{
                    TenantId   = $Context.Session.TenantId
                    DurationMs = 0
                    Timestamp  = Get-Date
                }
            }
        }

        $body.assignedTo = ''
    }

    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        if (-not (Test-XdrCapability -CapabilityName 'UpdateIncidentStatus' -Context $Context)) {
            return [pscustomobject]@{
                Success   = $false
                Operation = 'Set-XdrIncidentTriage'
                Message   = 'Capability not available: UpdateIncidentStatus'
                Data      = $null
                Error     = [pscustomobject]@{
                    Operation   = 'Set-XdrIncidentTriage'
                    SafeMessage = 'Capability not available: UpdateIncidentStatus'
                    Timestamp   = Get-Date
                }
                Metadata  = [ordered]@{
                    TenantId   = $Context.Session.TenantId
                    DurationMs = 0
                    Timestamp  = Get-Date
                }
            }
        }

        $graphStatus = Resolve-XdrGraphEnumValue -MapName 'incidentStatusMap' -DisplayValue $Status -Policy $Policy
        $body.status = $graphStatus
        $actionNames += "Set incident status to $Status"

        if ($graphStatus -eq 'resolved' -and [string]::IsNullOrWhiteSpace($Comment)) {
            $resolvedBy = $null
            if ($Context.Session -and $Context.Session.Analyst) {
                if (-not [string]::IsNullOrWhiteSpace($Context.Session.Analyst.DisplayName)) {
                    $resolvedBy = [string]$Context.Session.Analyst.DisplayName
                }
                elseif (-not [string]::IsNullOrWhiteSpace($Context.Session.Analyst.UserPrincipalName)) {
                    $resolvedBy = [string]$Context.Session.Analyst.UserPrincipalName
                }
                elseif (-not [string]::IsNullOrWhiteSpace($Context.Session.Analyst.Mail)) {
                    $resolvedBy = [string]$Context.Session.Analyst.Mail
                }
            }

            if ([string]::IsNullOrWhiteSpace($resolvedBy)) {
                $resolvedBy = 'current user'
            }

            $Comment = "Incident resolved by $resolvedBy using PwshXDRSpectre."
            $autoResolvedComment = $true
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Classification)) {
        if (-not (Test-XdrCapability -CapabilityName 'UpdateIncidentClassification' -Context $Context)) {
            return [pscustomobject]@{
                Success   = $false
                Operation = 'Set-XdrIncidentTriage'
                Message   = 'Capability not available: UpdateIncidentClassification'
                Data      = $null
                Error     = [pscustomobject]@{
                    Operation   = 'Set-XdrIncidentTriage'
                    SafeMessage = 'Capability not available: UpdateIncidentClassification'
                    Timestamp   = Get-Date
                }
                Metadata  = [ordered]@{
                    TenantId   = $Context.Session.TenantId
                    DurationMs = 0
                    Timestamp  = Get-Date
                }
            }
        }

        $body.classification = Resolve-XdrGraphEnumValue -MapName 'classifications' -DisplayValue $Classification -Policy $Policy
        $actionNames += 'Set incident classification'
    }

    if (-not [string]::IsNullOrWhiteSpace($Determination)) {
        if (-not (Test-XdrCapability -CapabilityName 'UpdateIncidentDetermination' -Context $Context)) {
            return [pscustomobject]@{
                Success   = $false
                Operation = 'Set-XdrIncidentTriage'
                Message   = 'Capability not available: UpdateIncidentDetermination'
                Data      = $null
                Error     = [pscustomobject]@{
                    Operation   = 'Set-XdrIncidentTriage'
                    SafeMessage = 'Capability not available: UpdateIncidentDetermination'
                    Timestamp   = Get-Date
                }
                Metadata  = [ordered]@{
                    TenantId   = $Context.Session.TenantId
                    DurationMs = 0
                    Timestamp  = Get-Date
                }
            }
        }

        $body.determination = Resolve-XdrGraphEnumValue -MapName 'determinations' -DisplayValue $Determination -Policy $Policy
        $actionNames += 'Set incident determination'
    }

    if (-not [string]::IsNullOrWhiteSpace($Comment)) {
        $body.comments = @(@{ comment = $Comment })
        if ($autoResolvedComment -or $Comment -eq $Policy.defaultResolvingComment) {
            $actionNames += 'Auto-fill resolving comment'
        }
    }

    if ($body.Count -eq 0) {
        return [pscustomobject]@{
            Success   = $false
            Operation = 'Set-XdrIncidentTriage'
            Message   = 'No triage changes were requested.'
            Data      = $null
            Error     = [pscustomobject]@{
                Operation   = 'Set-XdrIncidentTriage'
                SafeMessage = 'No triage changes were requested.'
                Timestamp   = Get-Date
            }
            Metadata  = [ordered]@{
                TenantId   = $Context.Session.TenantId
                DurationMs = 0
                Timestamp  = Get-Date
            }
        }
    }

    foreach ($actionName in $actionNames) {
        if ((Test-XdrActionSafetyPolicy -ActionName $actionName -Policy $Policy) -and -not $SkipConfirmation.IsPresent) {
            return [pscustomobject]@{
                Success   = $false
                Operation = 'Set-XdrIncidentTriage'
                Message   = 'Confirmation required before this incident triage action can run.'
                Data      = [pscustomobject]@{
                    ConfirmationRequired = $true
                    ActionName           = $actionName
                    Prompt               = (Get-XdrActionSafetyPolicy -ActionName $actionName -Policy $Policy).prompt
                    BodyParameter        = [pscustomobject]$body
                }
                Error     = $null
                Metadata  = [ordered]@{
                    TenantId   = $Context.Session.TenantId
                    DurationMs = 0
                    Timestamp  = Get-Date
                }
            }
        }
    }

    $operationResult = Invoke-XdrOperation -Operation 'Set-XdrIncidentTriage' -Context $Context -TargetObject $IncidentId -ScriptBlock {
        Update-MgSecurityIncident -IncidentId $IncidentId -BodyParameter $body
    } -SuccessMessage 'Updated incident triage successfully.' -FailureMessage 'Failed to update incident triage.'

    if ($operationResult.Success -and $Context.Selection.Incident -and $Context.Selection.Incident.IncidentId -eq $IncidentId) {
        if ($body.Contains('assignedTo')) {
            $Context.Selection.Incident.AssignedTo = $body.assignedTo
        }

        if ($body.Contains('status')) {
            $Context.Selection.Incident.Status = $body.status
        }

        if ($body.Contains('classification')) {
            $Context.Selection.Incident.Classification = $body.classification
        }

        if ($body.Contains('determination')) {
            $Context.Selection.Incident.Determination = $body.determination
        }
    }

    return $operationResult
}