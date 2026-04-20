function Start-PwshXdrDashboard {
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

    $context = New-XdrRuntimeContext -TenantId $TenantId -ClientId $ClientId -Mode 'menu' -ThemeColor 'Orange1'
    $connectResult = Connect-XdrSession -Context $context -UseDeviceCode:$UseDeviceCode.IsPresent

    if (-not $connectResult.Success) {
        Write-Error -Message $connectResult.Message
        return
    }

    $availableActions = @('Refresh', 'Assign to me', 'Investigate', 'Clear assignment')
    try {
        Write-Host "`e[?1049h"

        while ($true) {
            Clear-Host
            Write-SpectreFigletText -Text 'Hello XDR Spectre' -Alignment 'Left' -Color $context.Ui.ThemeColor -FigletFontPath "$PSScriptRoot/../ANSI Shadow.flf"

            $incidentsResult = Get-XdrIncidents -Context $context -Limit $Limit
            if (-not $incidentsResult.Success) {
                Write-SpectreHost "[red]$($incidentsResult.Message)[/]"
                break
            }

            $incidentTable = Format-XdrIncidentTable -Incidents $context.Data.Incidents -Color $context.Ui.ThemeColor
            $incidentTable | Out-SpectreHost
            Write-SpectreHost "Press [$($context.Ui.ThemeColor)]Ctrl+C[/] to exit."

            $action = Read-SpectreSelection -Title 'Choose an action: ' -Choices $availableActions -Color $context.Ui.ThemeColor
            if ($action -eq 'Refresh') {
                continue
            }

            $choices = @($context.Data.Incidents | ForEach-Object {
                [pscustomobject]@{
                    Label      = "$($_.IncidentId) - $($_.DisplayName)"
                    IncidentId = $_.IncidentId
                    Item       = $_
                }
            })

            if (-not $choices) {
                Write-SpectreHost '[yellow]No incident to select.[/]'
                continue
            }

            $selected = Read-SpectreSelection -Title "Select the [$($context.Ui.ThemeColor)]incident[/]: " -Choices $choices -Color $context.Ui.ThemeColor -ChoiceLabelProperty 'Label'
            $context.Selection.Incident = $selected.Item

            switch ($action) {
                'Assign to me' {
                    $mail = $context.Session.Analyst.Mail
                    $assignResult = Invoke-XdrOperation -Operation 'AssignIncidentToMe' -Context $context -TargetObject $context.Selection.Incident.IncidentId -ScriptBlock {
                        Update-MgSecurityIncident -IncidentId $context.Selection.Incident.IncidentId -BodyParameter @{ assignedTo = $mail }
                    } -SuccessMessage 'Assigned incident successfully.' -FailureMessage 'Failed to assign incident.'

                    Write-SpectreHost $(if ($assignResult.Success) { "[green]$($assignResult.Message)[/]" } else { "[red]$($assignResult.Message)[/]" })
                }
                'Investigate' {
                    $alertsResult = Get-XdrAlerts -Context $context -Incident $context.Selection.Incident
                    if ($alertsResult.Success) {
                        $alertPreview = @($alertsResult.Data | Select-Object AlertId, Title, Status, Severity, CreatedDateTime)
                        if ($alertPreview) {
                            Format-SpectreTable -Data $alertPreview -Color $context.Ui.ThemeColor | Out-SpectreHost
                        }
                        else {
                            Write-SpectreHost '[yellow]No alerts on selected incident.[/]'
                        }
                    }
                    else {
                        Write-SpectreHost "[red]$($alertsResult.Message)[/]"
                    }
                }
                'Clear assignment' {
                    $clearResult = Invoke-XdrOperation -Operation 'ClearIncidentAssignment' -Context $context -TargetObject $context.Selection.Incident.IncidentId -ScriptBlock {
                        Update-MgSecurityIncident -IncidentId $context.Selection.Incident.IncidentId -BodyParameter @{ assignedTo = '' }
                    } -SuccessMessage 'Cleared incident assignment.' -FailureMessage 'Failed to clear incident assignment.'

                    Write-SpectreHost $(if ($clearResult.Success) { "[green]$($clearResult.Message)[/]" } else { "[red]$($clearResult.Message)[/]" })
                }
            }

            Start-Sleep -Seconds 1
        }
    }
    finally {
        Write-Host "`e[?1049l"
    }
}