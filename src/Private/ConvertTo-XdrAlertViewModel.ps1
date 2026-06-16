function ConvertTo-XdrAlertViewModel {
    <#
    .SYNOPSIS
    Converts a Graph alert into the dashboard alert view model.

    .DESCRIPTION
    Projects the alert fields needed by the live dashboard and preserves the
    parent incident id for cache and selection tracking.

    .PARAMETER Alert
    Source alert object.

    .PARAMETER IncidentId
    Incident id associated with the alert.

    .OUTPUTS
    System.Management.Automation.PSCustomObject

    .EXAMPLE
    ConvertTo-XdrAlertViewModel -Alert $alert -IncidentId $incidentId
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Alert,

        [Parameter(Mandatory)]
        [string]$IncidentId
    )

    [pscustomobject]@{
        AlertId          = $Alert.Id
        Title            = $Alert.Title
        Status           = $Alert.Status
        Severity         = $Alert.Severity
        CreatedDateTime  = $Alert.CreatedDateTime
        AlertWebUrl      = $Alert.AlertWebUrl
        IncidentId       = $IncidentId
        Evidence         = @($Alert.Evidence)
        Entities         = @($Alert.Entities)
    }
}