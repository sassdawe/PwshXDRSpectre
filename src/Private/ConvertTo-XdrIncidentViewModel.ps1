function ConvertTo-XdrIncidentViewModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Incident,

        [Parameter(Mandatory)]
        [string]$TenantId
    )

    $incidentId = [string]$Incident.Id
    $tenantIdValue = [string]$TenantId
    $incidentWebUrl = $null
    if (-not [string]::IsNullOrWhiteSpace($incidentId) -and -not [string]::IsNullOrWhiteSpace($tenantIdValue)) {
        $incidentWebUrl = "https://security.microsoft.com/incident2/$incidentId/overview?tid=$tenantIdValue"
    }

    [pscustomobject]@{
        IncidentId      = $Incident.Id
        DisplayName     = $Incident.DisplayName
        Status          = $Incident.Status
        Severity        = $Incident.Severity
        Classification  = $Incident.Classification
        AssignedTo      = $Incident.AssignedTo
        Determination   = $Incident.Determination
        CreatedDateTime = $Incident.CreatedDateTime
        LastUpdateDateTime = $Incident.LastUpdateDateTime
        AlertCount      = @($Incident.Alerts).Count
        AlertRefs       = @($Incident.Alerts)
        SystemTags      = @($Incident.SystemTags)
        CustomTags      = @($Incident.CustomTags)
        IncidentWebUrl  = $incidentWebUrl
        TenantId        = $TenantId
        RawObject       = $Incident
    }
}