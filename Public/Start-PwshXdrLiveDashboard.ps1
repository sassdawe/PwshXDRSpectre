function Start-PwshXdrLiveDashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [switch]$UseDeviceCode
    )

    $context = New-XdrRuntimeContext -TenantId $TenantId -ClientId $ClientId -Mode 'live' -ThemeColor 'Orange1'

    $layout = New-SpectreLayout -Name 'root' -Rows @(
        (New-SpectreLayout -Name 'header' -MinimumSize 5 -Ratio 2 -Data 'empty'),
        (
            New-SpectreLayout -Name 'incident_content' -Ratio 5 -Columns @(
                (New-SpectreLayout -Name 'incidents' -Ratio 2 -Data 'empty'),
                (New-SpectreLayout -Name 'incident_details' -Ratio 4 -Data 'empty')
            )
        ),
        (
            New-SpectreLayout -Name 'alert_content' -Ratio 5 -Columns @(
                (New-SpectreLayout -Name 'alerts' -Ratio 2 -Data 'empty'),
                (New-SpectreLayout -Name 'alert_details' -Ratio 4 -Data 'empty')
            )
        )
    )

    Invoke-SpectreLive -Data $layout -ScriptBlock {
        param([Spectre.Console.LiveDisplayContext]$LiveContext)

        $authAttempted = $false
        $authSucceeded = $false
        $dataLoaded = $false
        $fatalErrorMessage = $null

        $selectedIndex = 0
        $selectedIncident = $null
        $selectedAlert = $null

        while ($true) {
            if (-not $authAttempted) {
                $header = Write-SpectreFigletText -Text 'Hello XDR Spectre' -Alignment 'Center' -Color $context.Ui.ThemeColor -FigletFontPath "$PSScriptRoot/../ANSI Shadow.flf" -PassThru | Format-SpectrePanel -Expand
                $layout['header'].Update($header) | Out-Null
                $layout['incidents'].Update((Format-SpectrePanel -Header '[white]Incident List[/]' -Data 'Preparing authentication...' -Expand)) | Out-Null
                $layout['incident_details'].Update((Format-SpectrePanel -Header '[white]Incident Details[/]' -Data 'Preparing authentication...' -Expand)) | Out-Null
                $layout['alerts'].Update((Format-SpectrePanel -Header '[white]Alert List[/]' -Data 'Preparing authentication...' -Expand)) | Out-Null
                $layout['alert_details'].Update((Format-SpectrePanel -Header '[white]Alert Details[/]' -Data 'Preparing authentication...' -Expand)) | Out-Null
                $LiveContext.Refresh()

                $authAttempted = $true
                $layout['incidents'].Update((Format-SpectrePanel -Header '[white]Incident List[/]' -Data 'Authenticating with Microsoft Graph...' -Expand)) | Out-Null
                $layout['incident_details'].Update((Format-SpectrePanel -Header '[white]Incident Details[/]' -Data 'Authenticating with Microsoft Graph...' -Expand)) | Out-Null
                $LiveContext.Refresh()

                $connectResult = Connect-XdrSession -Context $context -UseDeviceCode:$UseDeviceCode.IsPresent
                if (-not $connectResult.Success) {
                    $fatalErrorMessage = $connectResult.Message
                }
                else {
                    $authSucceeded = $true
                }

                continue
            }

            if (-not $authSucceeded) {
                $layout['header'].Update("[red]Authentication failed: $fatalErrorMessage[/]") | Out-Null
                $layout['incidents'].Update((Format-SpectrePanel -Header '[white]Incident List[/]' -Data 'Press Escape to exit.' -Expand)) | Out-Null
                $layout['incident_details'].Update((Format-SpectrePanel -Header '[white]Incident Details[/]' -Data 'No data available.' -Expand)) | Out-Null
                $layout['alerts'].Update((Format-SpectrePanel -Header '[white]Alert List[/]' -Data 'No data available.' -Expand)) | Out-Null
                $layout['alert_details'].Update((Format-SpectrePanel -Header '[white]Alert Details[/]' -Data 'No data available.' -Expand)) | Out-Null
                $LiveContext.Refresh()

                $keyOnError = Get-XdrLastKeyPressed
                if ($keyOnError -and $keyOnError.Key -eq 'Escape') {
                    return
                }

                Start-Sleep -Milliseconds $context.Ui.RefreshIntervalMs
                continue
            }

            if (-not $dataLoaded) {
                $layout['header'].Update('[yellow]Connected. Loading incidents...[/]') | Out-Null
                $layout['incidents'].Update((Format-SpectrePanel -Header '[white]Incident List[/]' -Data 'Loading incidents...' -Expand)) | Out-Null
                $layout['incident_details'].Update((Format-SpectrePanel -Header '[white]Incident Details[/]' -Data 'Loading incidents...' -Expand)) | Out-Null
                $LiveContext.Refresh()

                $incidentsResult = Get-XdrIncidents -Context $context -Limit $Limit
                if (-not $incidentsResult.Success) {
                    $fatalErrorMessage = $incidentsResult.Message
                    $authSucceeded = $false
                    continue
                }

                $dataLoaded = $true
                if ($context.Data.Incidents.Count -gt 0) {
                    $selectedIndex = 0
                    $selectedIncident = $context.Data.Incidents[$selectedIndex]
                    $context.Selection.Incident = $selectedIncident
                }
                continue
            }

            $key = Get-XdrLastKeyPressed
            if ($key -ne $null) {
                if ($key.Key -eq 'Escape') {
                    return
                }

                if (-not $selectedIncident) {
                    continue
                }

                if ($key.Key -eq 'DownArrow') {
                    $selectedIndex = ($selectedIndex + 1) % $context.Data.Incidents.Count
                    $selectedIncident = $context.Data.Incidents[$selectedIndex]
                    $context.Selection.Incident = $selectedIncident
                }
                elseif ($key.Key -eq 'UpArrow') {
                    $selectedIndex = ($selectedIndex - 1 + $context.Data.Incidents.Count) % $context.Data.Incidents.Count
                    $selectedIncident = $context.Data.Incidents[$selectedIndex]
                    $context.Selection.Incident = $selectedIncident
                }
                elseif ($key.Key -eq 'Enter') {
                    $alertsResult = Get-XdrAlerts -Context $context -Incident $selectedIncident
                    if ($alertsResult.Success -and $alertsResult.Data.Count -gt 0) {
                        $selectedAlert = $alertsResult.Data[0]
                        $context.Selection.Alert = $selectedAlert
                    }
                    else {
                        $selectedAlert = $null
                        $context.Selection.Alert = $null
                    }
                }
            }

            $header = Write-SpectreFigletText -Text 'Hello XDR Spectre' -Alignment 'Center' -Color $context.Ui.ThemeColor -FigletFontPath "$PSScriptRoot/../ANSI Shadow.flf" -PassThru | Format-SpectrePanel -Expand

            if (-not $context.Data.Incidents) {
                $layout['header'].Update($header) | Out-Null
                $layout['incidents'].Update((Format-SpectrePanel -Header '[white]Incident List[/]' -Data 'No incidents found. Press Escape to exit.' -Expand)) | Out-Null
                $layout['incident_details'].Update((Format-SpectrePanel -Header '[white]Incident Details[/]' -Data 'No incident selected.' -Expand)) | Out-Null
                $layout['alerts'].Update((Format-SpectrePanel -Header '[white]Alert List[/]' -Data 'No incident selected.' -Expand)) | Out-Null
                $layout['alert_details'].Update((Format-SpectrePanel -Header '[white]Alert Details[/]' -Data 'No alert selected.' -Expand)) | Out-Null
                $LiveContext.Refresh()
                Start-Sleep -Milliseconds $context.Ui.RefreshIntervalMs
                continue
            }

            $incidentLines = $context.Data.Incidents | ForEach-Object {
                if ($_.IncidentId -eq $selectedIncident.IncidentId) {
                    "[Turquoise2]$($_.DisplayName)[/]"
                }
                else {
                    $_.DisplayName
                }
            }

            $incidentPanel = Format-SpectrePanel -Header "[white]Incident List ($($context.Data.Incidents.Count))[/]" -Data (($incidentLines | Out-String)) -Expand

            $incidentDetails = [pscustomobject]@{
                IncidentId    = $selectedIncident.IncidentId
                DisplayName   = $selectedIncident.DisplayName
                Status        = $selectedIncident.Status
                Determination = $selectedIncident.Determination
                AssignedTo    = $selectedIncident.AssignedTo
                Severity      = $selectedIncident.Severity
                AlertCount    = $selectedIncident.AlertCount
                Created       = $selectedIncident.CreatedDateTime
            } | Format-SpectreJson | Format-SpectrePanel -Header '[white]Incident Details[/]' -Expand

            $alertLines = if ($context.Data.Alerts) {
                $context.Data.Alerts | ForEach-Object {
                    if ($selectedAlert -and $_.AlertId -eq $selectedAlert.AlertId) {
                        "[Turquoise2]$($_.Title)[/]"
                    }
                    else {
                        $_.Title
                    }
                }
            }
            else {
                @('Press Enter on an incident to load alerts.')
            }

            $alertsPanel = Format-SpectrePanel -Header "[white]Alert List ($($context.Data.Alerts.Count))[/]" -Data (($alertLines | Out-String)) -Expand

            $alertDetails = if ($selectedAlert) {
                [pscustomobject]@{
                    AlertId     = $selectedAlert.AlertId
                    Title       = $selectedAlert.Title
                    Status      = $selectedAlert.Status
                    Severity    = $selectedAlert.Severity
                    Created     = $selectedAlert.CreatedDateTime
                    AlertWebUrl = $selectedAlert.AlertWebUrl
                } | Format-SpectreJson | Format-SpectrePanel -Header '[white]Alert Details[/]' -Expand
            }
            else {
                Format-SpectrePanel -Header '[white]Alert Details[/]' -Data 'No alert selected.' -Expand
            }

            $layout['header'].Update($header) | Out-Null
            $layout['incidents'].Update($incidentPanel) | Out-Null
            $layout['incident_details'].Update($incidentDetails) | Out-Null
            $layout['alerts'].Update($alertsPanel) | Out-Null
            $layout['alert_details'].Update($alertDetails) | Out-Null
            $LiveContext.Refresh()

            Start-Sleep -Milliseconds $context.Ui.RefreshIntervalMs
        }
    }
}