function Sync-XdrLiveCachedDataToIncidents {
    <#
    .SYNOPSIS
    Removes cached incident data for incidents no longer present.

    .DESCRIPTION
    Compares active incident ids against one or more cache tables and removes
    entries whose incident ids are no longer part of the current incident set.

    .PARAMETER Incidents
    Current incident collection.

    .PARAMETER CacheTables
    Cache tables keyed by incident id.

    .OUTPUTS
    None

    .EXAMPLE
    Sync-XdrLiveCachedDataToIncidents -Incidents $context.Data.Incidents -CacheTables @($alertsByIncidentId, $entitiesByIncidentId)
    #>
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
