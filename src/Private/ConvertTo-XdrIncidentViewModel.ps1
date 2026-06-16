function ConvertTo-XdrIncidentViewModel {
    <#
    .SYNOPSIS
    Converts a Graph incident into the dashboard incident view model.

    .DESCRIPTION
    Projects the incident fields used by the live dashboard and derives the
    Defender portal incident URL when both tenant and incident identifiers are
    available.

    .PARAMETER Incident
    Source incident object.

    .PARAMETER TenantId
    Tenant id used to build the incident web URL.

    .OUTPUTS
    System.Management.Automation.PSCustomObject

    .EXAMPLE
    ConvertTo-XdrIncidentViewModel -Incident $incident -TenantId $context.Session.TenantId
    #>
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