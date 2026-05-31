function Sync-XdrLiveCachedDataToIncidents {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Incidents,

        [Parameter(Mandatory)]
        [hashtable[]]$CacheTables
    )

    $activeIncidentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($incident in @($Incidents)) {
        if (-not $incident) {
            continue
        }

        $incidentId = [string]$incident.IncidentId
        if ([string]::IsNullOrWhiteSpace($incidentId)) {
            continue
        }

        [void]$activeIncidentIds.Add($incidentId)
    }

    foreach ($cacheTable in @($CacheTables)) {
        foreach ($cacheKey in @($cacheTable.Keys)) {
            if (-not $activeIncidentIds.Contains([string]$cacheKey)) {
                $cacheTable.Remove($cacheKey)
            }
        }
    }
}
