function Format-XdrIncidentTable {
    <#
    .SYNOPSIS
    Formats incidents for tabular dashboard display.

    .DESCRIPTION
    Projects incident properties into table rows and returns either a formatted
    Spectre table or an empty-state message when no incidents are available.

    .PARAMETER Incidents
    Incident collection to format.

    .PARAMETER Color
    Accent color used by the rendered table.

    .OUTPUTS
    System.Object

    .EXAMPLE
    Format-XdrIncidentTable -Incidents $context.Data.Incidents -Color 'Orange1'
    #>
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