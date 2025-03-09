function Update-IncidentTable {
    [CmdletBinding()]
    param (
        #[Parameter(Mandatory=$true)]
        #[string[]]$tenantId,
        #[Parameter(Mandatory=$true)]
        #[string[]]$AwsRegions
    )

    Clear-Host
 #   Write-SpectreFigletText -Text "EC2" -Color Orange1 -FigletFontPath "$PSScriptRoot/../fonts/ANSI Shadow.flf"
    Write-SpectreFigletText -Text "Hello XDR Spectre" -Alignment "Left" -Color Orange1 -FigletFontPath "$PSScriptRoot/ANSI Shadow.flf"


    $cursorPosition = $Host.UI.RawUI.CursorPosition
 #   [Console]::SetCursorPosition($cursorPosition.X + 25, $cursorPosition.Y - 4)
 #   Write-Host -NoNewline "Extremely"
 #   [Console]::SetCursorPosition($cursorPosition.X + 25, $cursorPosition.Y - 3)
 #   Write-Host -NoNewline "Common"
 #   [Console]::SetCursorPosition($cursorPosition.X + 25, $cursorPosition.Y - 2)
 #   Write-Host -NoNewline "Commands"
    [Console]::SetCursorPosition($cursorPosition.X, $cursorPosition.Y)

    $mgIncidents = if ($limit) { Get-MgSecurityIncident | Select-Object -First $limit } else { Get-MgSecurityIncident }

    $data = foreach ($incident in $mgIncidents) {
        $sev = switch ( "$($incident.severity)" ) {
                "low" { "[green]low[/]" }
                "medium" { "[blue]medium[/]" }
                "high" { "[red]high[/]" }
                default { "[white]$($incident.severity)[/]" }
            }
        $state = switch( "$($incident.Status)" ) {
                "active" { "[red]active[/]" }
                "inProgress" { "[blue]inProgress[/]" }
                "resolved" { "[green]resolved[/]" }
                default { "[yellow]$($incident.Status)[/]" }
            }
            
        
        $incidentData = [ordered]@{
            "IncidentId" = $incident.ID
            "DisplayName" = $incident.DisplayName
            "Status" = $incident.Status
            "Determination" = $incident.Determination
            "CustomTags" = $incident.CustomTags
            "Created" = $incident.CreatedDateTime
            "AssignedTo" = $incident.AssignedTo
            "Severity" = $sev

            #"Alerts" = $incident.alerts
        }

        $alertData = foreach ($alertMeta in $incident.alerts) {
            #Get-MgSecurityAlertV2 -AlertId $alert.id | Select-Object @{"Name"="Link";"Expression"={ "$($_.Status), $($_.CreatedDateTime), [green]$($_.Title.trim())[/]"}}
            #Get-MgSecurityAlertV2 -AlertId $alert.id | Select-Object Status, CreatedDateTime, @{"Name"="Link";"Expression"={ "[green]$($_.Title.trim())[/]"} }
            $alerts = Get-MgSecurityAlertV2 -AlertId $alertMeta.id 
            $alertMetaData = foreach ($alert in $alerts ) {
                $link = Write-SpectreHost "[blue][link=$($alert.AlertWebUrl)]$($alert.Title)[/][/]" -PassThru
                $stat = switch ( "$($alert.Status)") {
                    "resolved" { "[green]resolved[/]" }
                    "inProgress" { "[blue]inProgress[/]" }
                    "new" { "[red]new[/]" }
                    default { "[white]$(alert.Status)[/]" }
                }
                $am = [ordered]@{
                    "Status" = $stat
                    "Created" = $alert.CreatedDateTime
                    "Link" = $link
                }

                $am
            }
            $alertMetaData
            #Get-MgSecurityAlertV2 -AlertId $alert.id | Select-Object @{"Name"="Link";"Expression"={ "$($_.Status), $($_.CreatedDateTime), [link=$($_.AlertWebUrl.Trim())]$($_.Title.trim())[/]"}}
            #Get-MgSecurityAlertV2 -AlertId $alert.id | ForEach-Object { "[link=$($_.AlertWebUrl)]$($alert.id)[/]" } 
        }

        $alertTable = Format-SpectreTable -Color Orange1 -Data $alertData -HideHeaders -Expand -Border None -AllowMarkup
        #$table | Out-SpectreHost
        #$incidentData.Add("Alerts", $(Format-SpectreTable -AllowMarkup -Color Orange1 -Data $alertData -HideHeaders -Expand))
        $incidentData.Add("Alerts (Status | Created | Title/Link)", $alertTable)
        $incidentData
    }

    

    try {
        $table = Format-SpectreTable -Data $data -AllowMarkup:$false -Color Orange1
        $table | Out-SpectreHost
    } catch {
        Write-SpectreHost "There are not open incidents, all in the [green]green[/]."
    }

    $script:metaIncidents = $data | Select-Object `
        @{
            Name="DisplayName"
            Expression={$_.DisplayName}
        },
        @{
            Name="IncidentId"
            Expression={$_.IncidentId}
        },
        @{
            Name="Name (IncidentId)"
            Expression={"$($_.IncidentId) - $($_.DisplayName)"}
        }

    Write-Host ""
    #return $incidents
}
#}
