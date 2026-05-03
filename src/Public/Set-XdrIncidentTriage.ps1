function Set-XdrIncidentTriage {
    <#
        .SYNOPSIS
        Applies one or more triage attributes to a Microsoft Defender XDR incident.

        .DESCRIPTION
        Builds a Microsoft Graph PATCH payload from any combination of Status,
        Classification, Determination, and assignment parameters, enforces capability
        guards and safety policy confirmations, posts the update, and optionally
        appends a comment to the incident activity feed.

        .PARAMETER Context
        The runtime context object that holds session, capability, and selection state.

        .PARAMETER IncidentId
        The unique identifier of the incident to update.

        .PARAMETER Status
        The human-readable incident status to apply (e.g., 'Active', 'In progress', 'Resolved').

        .PARAMETER Classification
        The classification label to apply (e.g., 'True positive', 'False positive').

        .PARAMETER Determination
        The determination label to apply (e.g., 'Malware', 'Phishing').

        .PARAMETER Comment
        An analyst comment to append to the incident activity feed.

        .PARAMETER AssignedTo
        The email address or UPN of the analyst to assign the incident to.
        Must match the format user@domain.tld. Use -AssignToMe to assign to the
        current user, or -ClearAssignment to remove the assignment.

        .PARAMETER AssignToMe
        When specified, resolves the current user's identity and assigns the incident
        to that identity.

        .PARAMETER ClearAssignment
        When specified, removes any existing assignment from the incident.

        .PARAMETER SkipConfirmation
        When specified, bypasses safety policy confirmation prompts.

        .PARAMETER Policy
        The triage policy used for enum mapping and safety checks. Defaults to
        the policy returned by Get-XdrTriagePolicy.

        .OUTPUTS
        PSCustomObject containing Success, Operation, Message, Data, Error, and Metadata
        properties.

        .EXAMPLE
        Set-XdrIncidentTriage -Context $ctx -IncidentId 'inc-42' -Status 'Resolved' `
            -Classification 'True positive' -Determination 'Malware' -SkipConfirmation

        .EXAMPLE
        Set-XdrIncidentTriage -Context $ctx -IncidentId 'inc-42' -AssignToMe

        .NOTES
        Requires at least one of UpdateIncidentStatus, ClassifyIncident, or AssignIncident
        capabilities depending on which parameters are supplied.
    #>
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

        # Email address or UPN of the analyst to assign the incident to. Ignored if AssignToMe or ClearAssignment is specified.
        [Parameter()]
        [ValidateScript({ $_ -match '^[^@\s]+@[^@\s]+\.[^@\s]+$' }, ErrorMessage = 'AssignedTo must be a valid email address or UPN.')]
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
    $normalComment = $null
    $shouldPostIncidentComment = $false

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
        if ($body.status -eq 'resolved') {
            $body.resolvingComment = $Comment
            if ($autoResolvedComment -or $Comment -eq $Policy.defaultResolvingComment) {
                $actionNames += 'Auto-fill resolving comment'
            }
        }
        else {
            $normalComment = $Comment
            $shouldPostIncidentComment = $true
        }
    }

    if ($body.Count -eq 0 -and -not $shouldPostIncidentComment) {
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

    $operationResult = $null

    if ($body.Count -gt 0) {
        $operationResult = Invoke-XdrOperation -Operation 'Set-XdrIncidentTriage' -Context $Context -TargetObject $IncidentId -ScriptBlock {
            Update-MgSecurityIncident -IncidentId $IncidentId -BodyParameter $body
        } -SuccessMessage 'Updated incident triage successfully.' -FailureMessage 'Failed to update incident triage.'

        if (-not $operationResult.Success) {
            return $operationResult
        }
    }

    if ($shouldPostIncidentComment) {
        $commentPayload = @{
            '@odata.type' = 'microsoft.graph.security.alertComment'
            comment       = $normalComment
        }

        $encodedIncidentId = [uri]::EscapeDataString([string]$IncidentId)
        $commentUri = "/v1.0/security/incidents/$encodedIncidentId/comments"

        $commentResult = Invoke-XdrOperation -Operation 'Set-XdrIncidentTriage' -Context $Context -TargetObject $IncidentId -ScriptBlock {
            Invoke-MgGraphRequest -Method POST -Uri $commentUri -ContentType 'application/json' -Body ($commentPayload | ConvertTo-Json -Depth 5 -Compress)
        } -SuccessMessage 'Added incident comment successfully.' -FailureMessage 'Failed to add incident comment.'

        if (-not $commentResult.Success) {
            return $commentResult
        }

        if ($null -eq $operationResult) {
            $operationResult = $commentResult
        }
    }

    if ($null -eq $operationResult) {
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

        if ($body.Contains('resolvingComment')) {
            if ($Context.Selection.Incident.PSObject.Properties.Name -contains 'ResolvingComment') {
                $Context.Selection.Incident.ResolvingComment = $body.resolvingComment
            }
            else {
                $Context.Selection.Incident | Add-Member -MemberType NoteProperty -Name 'ResolvingComment' -Value $body.resolvingComment -Force
            }
        }
    }

    return $operationResult
}