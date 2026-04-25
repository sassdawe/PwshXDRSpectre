function Update-IncidentTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    Clear-Host
    Write-SpectreFigletText -Text 'Hello XDR Spectre' -Alignment 'Left' -Color $Context.Ui.ThemeColor -FigletFontPath "$PSScriptRoot/ANSI Shadow.flf"

    $rows = foreach ($incident in $Context.Data.Incidents) {
        [pscustomobject]@{
            IncidentId    = $incident.IncidentId
            DisplayName   = $incident.DisplayName
            Status        = $incident.Status
            Determination = $incident.Determination
            AssignedTo    = $incident.AssignedTo
            Severity      = $incident.Severity
            AlertCount    = $incident.AlertCount
            Created       = $incident.CreatedDateTime
        }
    }

    if (-not $rows) {
        Write-SpectreHost '[yellow]No incidents found.[/]'
        return
    }

    Format-SpectreTable -Data $rows -Color $Context.Ui.ThemeColor | Out-SpectreHost
}
