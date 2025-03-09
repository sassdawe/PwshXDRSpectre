#Requires -Version 7 -Modules PwshSpectreConsole, Microsoft.Graph.Authentication, Microsoft.Graph.Security

[CmdletBinding()]
param (
    [system.string[]]$tenantId,
    [system.string]$clientID,
    [int]$limit
)

. "$PSScriptRoot/Update-IncidentTable.ps1"

$PSDefaultParameterValues["Connect-MgGraph:NoWelcome"] = $true

$PSDefaultParameterValues["Get-MgSecurityIncident:ExpandProperty"] = @('Alerts')

$color = "Orange1"

foreach ($tId in $tenantId) {
    Connect-MgGraph -TenantId $tId -ClientId $clientID -ContextScope CurrentUser -NoWelcome:$true -UseDeviceCode:$false
}

$Script:metaIncidents = $null

try {
    Write-Host "`e[?1049h" # alt screen buffer
    $me = Invoke-MgGraphRequest -Method GET -Uri /v1.0/me | Select-Object -Property id, displayName, userPrincipalName, mail

    $availableActions = @("Refresh", "Assign to me", "Investigate","Clear assigment")

    while($true) {

        Update-IncidentTable #$tenantId

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