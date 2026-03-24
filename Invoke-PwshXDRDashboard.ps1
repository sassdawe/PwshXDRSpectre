#Requires -Version 7 -Modules PwshSpectreConsole, Microsoft.Graph.Authentication, Microsoft.Graph.Security

[CmdletBinding()]
param (
    [system.string[]]$tenantId,
    [system.string]$clientID,
    [int]$limit
)

#. "$PSScriptRoot/Update-IncidentTable.ps1"

$layout = New-SpectreLayout -Name "root" -Rows @(
    (
        New-SpectreLayout -Name "header" -MinimumSize 5 -Ratio 2 -Data ("empty")
    ),
    (
        New-SpectreLayout -Name "incident_content" -Ratio 5 -Columns @(
            (
                New-SpectreLayout -Name "incidents" -Ratio 2 -Data "empty"
            ),
            (
                New-SpectreLayout -Name "incident_details" -Ratio 4 -Data "empty"
            )
        )
    ),
    (
        New-SpectreLayout -Name "alert_content" -Ratio 5 -Columns @(
            (
                New-SpectreLayout -Name "alerts" -Ratio 2 -Data "empty"
            ),
            (
                New-SpectreLayout -Name "alert_details" -Ratio 4 -Data "empty"
            )
        )
    )
)
function Get-TitlePanel {
    return (Write-SpectreFigletText -Text "Hello XDR Spectre" -Alignment "Center" -Color Orange1 -FigletFontPath "$PSScriptRoot/ANSI Shadow.flf" -PassThru | Format-SpectrePanel -Expand) 
    #return "Hello XDR Spectre [gray]$(Get-Date)[/]" | Format-SpectreAligned -HorizontalAlignment Center -VerticalAlignment Middle | Format-SpectrePanel -Expand
}

function Get-IncidentListContent{
    param (
        $Incidents,
        $SelectedIncident
    )
    $incidentList = $Incidents | ForEach-Object {
        $name = $_.DisplayName
        #$id = $_.Id
        if ($_.id -eq $SelectedIncident.Id) {
            $name = "[Turquoise2]$($name)[/]"
        }
        #return "$id`t$name"
        return $name
    } | Out-String
    return Format-SpectrePanel -Header "[white]Incident List ($($Incidents.count))[/]" -Data $incidentList -Expand
}

function Get-IncidentDetailsContent {
    param (
        $SelectedIncident
    )
    #$item = Get-Item -Path $selectedIncident.FullName
    $result = ""
    $incident = $SelectedIncident
    try {
        #$content = Get-Content -Path $item.FullName -Raw -ErrorAction Stop
        #$result = "[grey]$($content | Get-SpectreEscapedText)[/]"

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
            
        
        $incidentData =  @(
            [pscustomobject]@{
            "IncidentId" = $incident.ID
            "DisplayName" = $incident.DisplayName
            "Status" = $incident.Status #  $state
            "Determination" = $incident.Determination
            "CustomTags" = $incident.CustomTags
            "Created" = $incident.CreatedDateTime
            "AssignedTo" = $incident.AssignedTo
            "Severity" = $incident.severity #$sev
            "AlertCount" = $incident.alerts.count

            #"Alerts" = $incident.alerts
        })
        $result = Format-SpectreJson -Data $incidentData

    } catch {
        $result = "[red]Error reading file content: $($_.Exception.Message | Get-SpectreEscapedText)[/]"
    }

    return $result | Format-SpectrePanel -Header "[white]Preview[/]" -Expand
}

function Get-AlertsListContent {
    param (
        $Alerts,
        $SelectedAlert
    )
    $alertList = $Alerts | ForEach-Object {
        $name = $_.Title
        #$id = $_.Id
        if ($_.id -eq $SelectedAlert.Id) {
            $name = "[Turquoise2]$($name)[/]"
        }
        return $name
    } | Out-String
    return Format-SpectrePanel -Header "[white]Alert List ($($Alerts.count))[/]" -Data $alertList -Expand
}

function Get-LastKeyPressed {
    $lastKeyPressed = $null
    while ([Console]::KeyAvailable) {
        $lastKeyPressed = [Console]::ReadKey($true)
    }
    return $lastKeyPressed
}

$PSDefaultParameterValues["Connect-MgGraph:NoWelcome"] = $true

$PSDefaultParameterValues["Get-MgSecurityIncident:ExpandProperty"] = @('Alerts')

$color = "Orange1"

while ($false) {
foreach ($tId in $tenantId) {
    Connect-MgGraph -TenantId $tId -ClientId $clientID -ContextScope CurrentUser -NoWelcome:$true -UseDeviceCode:$false
}

$Script:metaIncidents = $null

try {
    Write-Host "`e[?1049h" # alt screen buffer
    $me = Invoke-MgGraphRequest -Method GET -Uri /v1.0/me | Select-Object -Property id, displayName, userPrincipalName, mail

    $availableActions = @("Refresh", "Assign to me", "Investigate","Clear assigment")

    while($true) {

        #Update-IncidentTable #$tenantId
        $titlePanel = Get-TitlePanel






        Write-SpectreHost "Press [$color]Ctrl+C[/] to exit."

        $action = Read-SpectreSelection -Title "Choose an action: " -Choices $availableActions -Color $color
        Write-SpectreHost "Running [$color]$action[/]."

        if($action -eq "Refresh") {
            continue
        }

        $incident = Read-SpectreSelection -Title "Select the [$color]incident[/]: " -Choices $metaIncidents -Color $color -ChoiceLabelProperty "Name (IncidentId)"
        Write-SpectreHost "On [$color]$($incident."Name (IncidentId)")[/]."

        switch($action) {
            "Assign to me" {
                $params = @{
                    #classification = "falsePositive"
                    #determination = "other"
                    #status = "resolved"
                    #ResolvingComment = "Excluded, student"
                    assignedTo = $me.mail
                }

                $null = Update-MgSecurityIncident -IncidentId $incident.IncidentId -BodyParameter $params
            }
            "Investigate" {
                Write-SpectreHost "[red]Not implemented yet.[/]"
            }
            "Clear assigment" {
                $params = @{
                    assignedTo = ""
                }

                $null = Update-MgSecurityIncident -IncidentId $incident.IncidentId -BodyParameter $params
            }
            "Terminate" {
                <#$response = Read-SpectreConfirm -Prompt "Are you sure you want to terminate [$color]$($instance.'Name (InstanceId)')[/]?" -Color $color
                if($response -eq "y") {
                    Write-SpectreHost "Terminating [$color]$($instance.'Name (InstanceId)')[/]."
                    & aws ec2 terminate-instances --instance-ids $instance.InstanceId --profile $instance.Profile --region $instance.Region
                } else {
                    Write-SpectreHost "Not terminating [$color]$($instance.'Name (InstanceId)')[/]."
                }#>
            }
        }
        Start-Sleep -Seconds 1
        #$null = Read-Host
    }
} finally {
    Write-Host "`e[?1049l" # back to standard buffer
}
}

Invoke-SpectreLive -Data $layout -ScriptBlock {
    param (
        [Spectre.Console.LiveDisplayContext] $Context
    )
    $incidentList =  @(@{DisplayName = ".."; Id = 0}) + $(if ($limit) { Get-MgSecurityIncident | Select-Object -First $limit } else { Get-MgSecurityIncident -ExpandProperty Alerts })
    $selectedIncident = $incidentList[0]

    while ($true) {
        $lastKeyPressed = Get-LastKeyPressed
        if ($lastKeyPressed -ne $null) {
            if ($lastKeyPressed.Key -eq "DownArrow") {
                $selectedIncident = $incidentList[($incidentList.IndexOf($selectedIncident) + 1) % $incidentList.Count]
            } elseif ($lastKeyPressed.Key -eq "UpArrow") {
                $selectedIncident = $incidentList[($incidentList.IndexOf($selectedIncident) - 1 + $incidentList.Count) % $incidentList.Count]
            } elseif ($lastKeyPressed.Key -eq "Enter") {
                if ($selectedIncident.Name -ne "..") {
                    $alertList = $selectedIncident.alerts
                    $alertsListContent = Get-AlertsListContent -Alerts $alertList -SelectedAlert $alertList[0]
                    $layout["alerts"].Update($alertsListContent) | Out-Null
                } else {
                    $layout["alerts"].Update("empty") | Out-Null
                }
            } elseif ($lastKeyPressed.Key -eq "Escape") {
                return
            }
        }
        $titlePanel = Get-TitlePanel
        $incidentListContent = Get-IncidentListContent -Incidents $incidentList -SelectedIncident $selectedIncident
        $incidentDetailsContent = Get-IncidentDetailsContent -selectedIncident $selectedIncident
        
        $layout["header"].Update($titlePanel) | Out-Null
        $layout["incidents"].Update($incidentListContent) | Out-Null
        $layout["incident_details"].Update($incidentDetailsContent) | Out-Null
        $Context.Refresh()
        Start-Sleep -Milliseconds 200
    }
}