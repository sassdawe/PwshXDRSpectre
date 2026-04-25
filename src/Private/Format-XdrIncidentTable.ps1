function Format-XdrIncidentTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Incidents,

        [Parameter()]
        [string]$Color = 'Orange1'
    )

    $rows = foreach ($incident in $Incidents) {
        [pscustomobject]@{
            IncidentId    = $incident.IncidentId
            DisplayName   = $incident.DisplayName
            Status        = $incident.Status
            Severity      = $incident.Severity
            AssignedTo    = $incident.AssignedTo
            Determination = $incident.Determination
            AlertCount    = $incident.AlertCount
            Created       = $incident.CreatedDateTime
        }
    }

    if (-not $rows) {
        return '[yellow]No incidents found.[/]'
    }

    return Format-SpectreTable -Data $rows -Color $Color
}