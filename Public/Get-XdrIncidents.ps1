function Get-XdrIncidents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter()]
        [int]$Limit
    )

    $operationResult = Invoke-XdrOperation -Operation 'Get-XdrIncidents' -Context $Context -ScriptBlock {
        if ($Limit -gt 0) {
            Get-MgSecurityIncident -ExpandProperty Alerts | Select-Object -First $Limit
        }
        else {
            Get-MgSecurityIncident -ExpandProperty Alerts
        }
    } -SuccessMessage 'Retrieved incidents successfully.' -FailureMessage 'Failed to retrieve incidents.'

    if (-not $operationResult.Success) {
        return $operationResult
    }

    $tenantId = $Context.Session.TenantId
    $viewModels = @($operationResult.Data | ForEach-Object { ConvertTo-XdrIncidentViewModel -Incident $_ -TenantId $tenantId })
    $Context.Data.Incidents = $viewModels
    $Context.Data.LastRefresh = Get-Date

    return [pscustomobject]@{
        Success   = $true
        Operation = 'Get-XdrIncidents'
        Message   = "Retrieved $($viewModels.Count) incident(s)."
        Data      = $viewModels
        Error     = $null
        Metadata  = $operationResult.Metadata
    }
}