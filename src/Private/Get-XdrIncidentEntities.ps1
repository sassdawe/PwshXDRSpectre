function Get-XdrIncidentEntities {
    <#
    .SYNOPSIS
    Extracts related entities for an incident from loaded incident and alert data.

    .DESCRIPTION
    Produces a normalized in-memory list of related entities to power the
    related entities panel and entity-aware action previews.

    .PARAMETER Incident
    Incident view model or raw incident object.

    .PARAMETER Alerts
    Alert view models associated with the incident.

    .OUTPUTS
    System.Object[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Incident,

        [Parameter()]
        [object[]]$Alerts = @()
    )

    $incidentId = [string]$Incident.IncidentId
    if ([string]::IsNullOrWhiteSpace($incidentId) -and $Incident.PSObject.Properties.Name -contains 'Id') {
        $incidentId = [string]$Incident.Id
    }

    $entities = New-Object System.Collections.Generic.List[object]

    if (-not [string]::IsNullOrWhiteSpace([string]$Incident.AssignedTo)) {
        $entities.Add([pscustomobject]@{
                EntityType = 'User'
                DisplayName = [string]$Incident.AssignedTo
                UserPrincipalName = [string]$Incident.AssignedTo
                IncidentId = $incidentId
                AlertId = $null
                Source = 'Incident.AssignedTo'
            })
    }

    foreach ($alert in @($Alerts)) {
        $alertId = [string]$alert.AlertId
        $alertTitle = [string]$alert.Title

        if (-not [string]::IsNullOrWhiteSpace($alertTitle) -or -not [string]::IsNullOrWhiteSpace($alertId)) {
            $entities.Add([pscustomobject]@{
                    EntityType = 'Alert'
                    DisplayName = $(if (-not [string]::IsNullOrWhiteSpace($alertTitle)) { $alertTitle } else { $alertId })
                    AlertId = $alertId
                    IncidentId = $incidentId
                    Source = 'Alert'
                })
        }

        $rawAlert = $null
        if ($alert.PSObject.Properties.Name -contains 'RawObject') {
            $rawAlert = $alert.RawObject
        }

        if (-not $rawAlert) {
            $rawAlert = $null
        }

        $rawEntities = @()
        if ($alert.PSObject.Properties.Name -contains 'Evidence') {
            $rawEntities += @($alert.Evidence)
        }
        if ($alert.PSObject.Properties.Name -contains 'Entities') {
            $rawEntities += @($alert.Entities)
        }

        if ($rawAlert) {
            if ($rawAlert.PSObject.Properties.Name -contains 'Evidence') {
                $rawEntities += @($rawAlert.Evidence)
            }
            if ($rawAlert.PSObject.Properties.Name -contains 'Entities') {
                $rawEntities += @($rawAlert.Entities)
            }
        }

        foreach ($rawEntity in $rawEntities) {
            if (-not $rawEntity) {
                continue
            }

            $normalizedEntity = $rawEntity
            if ($rawEntity.PSObject.Properties.Name -contains 'AdditionalProperties' -and $rawEntity.AdditionalProperties) {
                try {
                    $normalizedEntity = [pscustomobject][hashtable]$rawEntity.AdditionalProperties
                }
                catch {
                    $normalizedEntity = $rawEntity
                }
            }

            $odataType = ''
            if ($normalizedEntity.PSObject.Properties.Name -contains '@odata.type') {
                $odataType = [string]$normalizedEntity.'@odata.type'
            }

            $entityType = [string]$normalizedEntity.EntityType
            if ([string]::IsNullOrWhiteSpace($entityType) -and $normalizedEntity.PSObject.Properties.Name -contains 'Type') {
                $entityType = [string]$normalizedEntity.Type
            }

            $displayName = $null
            if (-not [string]::IsNullOrWhiteSpace($odataType)) {
                switch -Regex ($odataType) {
                    'userEvidence$' {
                        if ($normalizedEntity.PSObject.Properties.Name -contains 'userAccount' -and $normalizedEntity.userAccount) {
                            $displayName = [string]$normalizedEntity.userAccount.userPrincipalName
                            if ([string]::IsNullOrWhiteSpace($displayName)) {
                                $displayName = [string]$normalizedEntity.userAccount.azureAdUserId
                            }
                            if ([string]::IsNullOrWhiteSpace($entityType)) { $entityType = 'User' }
                        }
                    }
                    'deviceEvidence$' {
                        $displayName = [string]$normalizedEntity.deviceDnsName
                        if ([string]::IsNullOrWhiteSpace($displayName)) {
                            $displayName = [string]$normalizedEntity.mdeDeviceId
                        }
                        if ([string]::IsNullOrWhiteSpace($entityType)) { $entityType = 'Device' }
                    }
                    'fileEvidence$' {
                        if ($normalizedEntity.PSObject.Properties.Name -contains 'fileDetails' -and $normalizedEntity.fileDetails) {
                            $displayName = [string]$normalizedEntity.fileDetails.sha256
                            if ([string]::IsNullOrWhiteSpace($displayName)) {
                                $displayName = [string]$normalizedEntity.fileDetails.fileName
                            }
                            if ([string]::IsNullOrWhiteSpace($entityType)) { $entityType = 'File' }
                        }
                    }
                    'ipEvidence$' {
                        $displayName = [string]$normalizedEntity.ipAddress
                        if ([string]::IsNullOrWhiteSpace($entityType)) { $entityType = 'IpAddress' }
                    }
                    'urlEvidence$' {
                        $displayName = [string]$normalizedEntity.url
                        if ([string]::IsNullOrWhiteSpace($entityType)) { $entityType = 'Url' }
                    }
                    'analyzedMessageEvidence$' {
                        if ($normalizedEntity.PSObject.Properties.Name -contains 'urls' -and $normalizedEntity.urls) {
                            foreach ($messageUrl in @($normalizedEntity.urls)) {
                                if ([string]::IsNullOrWhiteSpace([string]$messageUrl)) {
                                    continue
                                }

                                $entities.Add([pscustomobject]@{
                                        EntityType = 'Url'
                                        DisplayName = [string]$messageUrl
                                        IncidentId = $incidentId
                                        AlertId = $alertId
                                        Source = 'AlertEvidence'
                                        RawObject = $rawEntity
                                    })
                            }
                        }
                    }
                }
            }

            if ([string]::IsNullOrWhiteSpace($displayName)) {
                if ($normalizedEntity.PSObject.Properties.Name -contains 'DisplayName') {
                    $displayName = [string]$normalizedEntity.DisplayName
                }
                elseif ($normalizedEntity.PSObject.Properties.Name -contains 'UserPrincipalName') {
                    $displayName = [string]$normalizedEntity.UserPrincipalName
                    if ([string]::IsNullOrWhiteSpace($entityType)) { $entityType = 'User' }
                }
                elseif ($normalizedEntity.PSObject.Properties.Name -contains 'DeviceName') {
                    $displayName = [string]$normalizedEntity.DeviceName
                    if ([string]::IsNullOrWhiteSpace($entityType)) { $entityType = 'Device' }
                }
                elseif ($normalizedEntity.PSObject.Properties.Name -contains 'FileName') {
                    $displayName = [string]$normalizedEntity.FileName
                    if ([string]::IsNullOrWhiteSpace($entityType)) { $entityType = 'File' }
                }
                elseif ($normalizedEntity.PSObject.Properties.Name -contains 'Sha256') {
                    $displayName = [string]$normalizedEntity.Sha256
                    if ([string]::IsNullOrWhiteSpace($entityType)) { $entityType = 'File' }
                }
                elseif ($normalizedEntity.PSObject.Properties.Name -contains 'IpAddress') {
                    $displayName = [string]$normalizedEntity.IpAddress
                    if ([string]::IsNullOrWhiteSpace($entityType)) { $entityType = 'IpAddress' }
                }
                elseif ($normalizedEntity.PSObject.Properties.Name -contains 'Url') {
                    $displayName = [string]$normalizedEntity.Url
                    if ([string]::IsNullOrWhiteSpace($entityType)) { $entityType = 'Url' }
                }
            }

            if ([string]::IsNullOrWhiteSpace($displayName)) {
                continue
            }

            $entities.Add([pscustomobject]@{
                    EntityType = $(if ([string]::IsNullOrWhiteSpace($entityType)) { 'Entity' } else { $entityType })
                    DisplayName = $displayName
                    IncidentId = $incidentId
                    AlertId = $alertId
                    Source = 'AlertEvidence'
                    RawObject = $rawEntity
                })
        }
    }

    # Remove duplicates by entity type + display text within this incident.
    $seen = @{}
    $deduped = New-Object System.Collections.Generic.List[object]
    foreach ($entity in $entities) {
        $key = "{0}|{1}|{2}" -f [string]$entity.IncidentId, [string]$entity.EntityType, [string]$entity.DisplayName
        if ($seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        $deduped.Add($entity)
    }

    return $deduped.ToArray()
}
