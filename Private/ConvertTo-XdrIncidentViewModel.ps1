function ConvertTo-XdrIncidentViewModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Incident,

        [Parameter(Mandatory)]
        [string]$TenantId
    )

    [pscustomobject]@{
        IncidentId      = $Incident.Id
        DisplayName     = $Incident.DisplayName
        Status          = $Incident.Status
        Severity        = $Incident.Severity
        AssignedTo      = $Incident.AssignedTo
        Determination   = $Incident.Determination
        CreatedDateTime = $Incident.CreatedDateTime
        AlertCount      = @($Incident.Alerts).Count
        AlertRefs       = @($Incident.Alerts)
        TenantId        = $TenantId
        RawObject       = $Incident
    }
}