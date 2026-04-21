function Get-XdrActionDisableReasons {
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