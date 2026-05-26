function Start-XdrLiveEntityExtraction {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Incident,

        [Parameter(Mandatory)]
        [hashtable]$EntityLoadJobsByIncidentId,

        [Parameter(Mandatory)]
        [hashtable]$AlertsByIncidentId,

        [Parameter(Mandatory)]
        [string]$ModulePath,

        [Parameter()]
        [string]$DashboardLogPath
    )

    if (-not $Incident) {
        return
    }

    $incidentId = [string]$Incident.IncidentId
    if ([string]::IsNullOrWhiteSpace($incidentId)) {
        return
    }

    if ($EntityLoadJobsByIncidentId.ContainsKey($incidentId)) {
        return
    }

    $alertsForIncident = if ($AlertsByIncidentId.ContainsKey($incidentId)) {
        @($AlertsByIncidentId[$incidentId])
    }
    else {
        @()
    }

    $jobPayload = [pscustomobject]@{
        ModulePath       = $ModulePath
        IncidentData     = $Incident
        AlertData        = @($alertsForIncident)
        DashboardLogPath = $DashboardLogPath
        IncidentId       = $incidentId
    }

    $EntityLoadJobsByIncidentId[$incidentId] = Start-ThreadJob -ScriptBlock {
        param([object]$JobPayload)

        Import-Module $JobPayload.ModulePath -Force | Out-Null
        & (Get-Module PwshXDRSpectre) {
            param(
                [string]$InnerDashboardLogPath,
                [string]$InnerIncidentId
            )

            Write-XdrLiveDashboardLog -LogPath $InnerDashboardLogPath -Message "Entity extraction job started. IncidentId=$InnerIncidentId"
        } $JobPayload.DashboardLogPath $JobPayload.IncidentId
        & (Get-Module PwshXDRSpectre) {
            param(
                [object]$InnerIncidentData,
                [object[]]$InnerAlertData
            )

            Get-XdrIncidentEntities -Incident $InnerIncidentData -Alerts $InnerAlertData
        } $JobPayload.IncidentData @($JobPayload.AlertData)
    } -ArgumentList $jobPayload
}
