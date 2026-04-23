function Get-XdrAlerts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [object]$Incident
    )

    $incidentId = if ($Incident.IncidentId) { $Incident.IncidentId } else { $Incident.Id }
    $alertRefs = if ($Incident.AlertRefs) { @($Incident.AlertRefs) } elseif ($Incident.Alerts) { @($Incident.Alerts) } else { @() }

    if (-not $alertRefs) {
        $Context.Data.Alerts = @()
        return [pscustomobject]@{
            Success   = $true
            Operation = 'Get-XdrAlerts'
            Message   = 'No alerts on selected incident.'
            Data      = @()
            Error     = $null
            Metadata  = [ordered]@{
                TenantId   = $Context.Session.TenantId
                DurationMs = 0
                Timestamp  = Get-Date
            }
        }
    }

    $operationResult = Invoke-XdrOperation -Operation 'Get-XdrAlerts' -Context $Context -TargetObject $incidentId -ScriptBlock {
        foreach ($alertRef in $alertRefs) {
            Get-MgSecurityAlertV2 -AlertId $alertRef.Id
        }
    } -SuccessMessage 'Retrieved alerts for selected incident.' -FailureMessage 'Failed to retrieve alerts for selected incident.'

    if (-not $operationResult.Success) {
        return $operationResult
    }

    $viewModels = @($operationResult.Data | ForEach-Object { ConvertTo-XdrAlertViewModel -Alert $_ -IncidentId $incidentId })
    $Context.Data.Alerts = $viewModels

    return [pscustomobject]@{
        Success   = $true
        Operation = 'Get-XdrAlerts'
        Message   = "Retrieved $($viewModels.Count) alert(s)."
        Data      = $viewModels
        Error     = $null
        Metadata  = $operationResult.Metadata
    }
}