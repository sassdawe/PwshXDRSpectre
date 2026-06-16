function Get-XdrActionDisableReasons {
    <#
    .SYNOPSIS
    Returns the reasons an action should be disabled.

    .DESCRIPTION
    Evaluates policy restrictions, selection prerequisites, and status
    transition validity to produce the disable reasons shown in the action
    panel.

    .PARAMETER ActionName
    Display name of the action to evaluate.

    .PARAMETER Context
    Runtime context containing current selections and capabilities.

    .PARAMETER ActionType
    Entity type that the action targets.

    .PARAMETER CurrentStatus
    Current status of the selected object.

    .PARAMETER RequestedStatus
    Status requested by the action.

    .PARAMETER Policy
    Optional preloaded triage policy object.

    .OUTPUTS
    System.String[]

    .EXAMPLE
    Get-XdrActionDisableReasons -ActionName 'Set alert status to Resolved' -Context $context -ActionType Alert -CurrentStatus 'New' -RequestedStatus 'Resolved'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ActionName,

        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter()]
        [ValidateSet('Incident', 'Alert')]
        [string]$ActionType,

        [Parameter()]
        [string]$CurrentStatus,

        [Parameter()]
        [string]$RequestedStatus,

        [Parameter()]
        [object]$Policy = (Get-XdrTriagePolicy)
    )

    $reasons = @()
    $policyEntry = Get-XdrActionSafetyPolicy -ActionName $ActionName -Policy $Policy
    if ($policyEntry -and $policyEntry.level -eq 'disabled') {
        $reasons += 'Policy disabled'
    }

    switch ($ActionType) {
        'Incident' {
            if (-not $Context.Selection.Incident) {
                $reasons += 'Missing selection context: incident'
            }
        }
        'Alert' {
            if (-not $Context.Selection.Alert) {
                $reasons += 'Missing selection context: alert'
            }
        }
    }

    if ($RequestedStatus -and $CurrentStatus -and $RequestedStatus -eq $CurrentStatus) {
        $reasons += 'Invalid transition for current status'
    }

    $capabilityMap = @{
        'Assign incident to me' = 'AssignIncident'
        'Clear incident assignment' = 'ClearIncidentAssignment'
        'Set incident status to Active' = 'UpdateIncidentStatus'
        'Set incident status to In progress' = 'UpdateIncidentStatus'
        'Set incident status to Resolved' = 'UpdateIncidentStatus'
        'Set incident classification' = 'UpdateIncidentClassification'
        'Set incident determination' = 'UpdateIncidentDetermination'
        'Set alert status to New' = 'UpdateAlertStatus'
        'Set alert status to In progress' = 'UpdateAlertStatus'
        'Set alert status to Resolved' = 'UpdateAlertStatus'
    }

    if ($capabilityMap.Contains($ActionName)) {
        $capabilityName = $capabilityMap[$ActionName]
        if (-not (Test-XdrCapability -CapabilityName $capabilityName -Context $Context)) {
            $reasons += "Missing capability: $capabilityName"
        }
    }

    return @($reasons)
}