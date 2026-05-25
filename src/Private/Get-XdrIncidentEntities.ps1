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

    $newEntityRecord = {
        param(
            [string]$EntityType,
            [string]$DisplayName,
            [string]$AlertId,
            [string]$Source,
            [object]$RawObject,
            [object]$NormalizedEntity
        )

        $record = [ordered]@{
            EntityType  = $(if ([string]::IsNullOrWhiteSpace($EntityType)) { 'Entity' } else { $EntityType })
            DisplayName = $DisplayName
            IncidentId  = $incidentId
            AlertId     = $AlertId
            Source      = $Source
        }

        if ($null -ne $RawObject) {
            $record.RawObject = $RawObject
        }

        $sourceEntity = $NormalizedEntity
        if (-not $sourceEntity) {
            $sourceEntity = $RawObject
        }

        switch ($record.EntityType) {
            'User' {
                if ($sourceEntity -and $sourceEntity.PSObject.Properties.Name -contains 'UserId') {
                    $record.UserId = [string]$sourceEntity.UserId
                }
                elseif ($sourceEntity -and $sourceEntity.PSObject.Properties.Name -contains 'AzureAdUserId') {
                    $record.UserId = [string]$sourceEntity.AzureAdUserId
                }
                elseif ($sourceEntity -and $sourceEntity.PSObject.Properties.Name -contains 'userAccount' -and $sourceEntity.userAccount) {
                    $userAccount = $sourceEntity.userAccount
                    if ($userAccount -is [System.Collections.IDictionary]) {
                        if ($userAccount.Keys -contains 'azureAdUserId') {
                            $record.UserId = [string]$userAccount['azureAdUserId']
                        }
                        if ($userAccount.Keys -contains 'userPrincipalName') {
                            $record.UserPrincipalName = [string]$userAccount['userPrincipalName']
                        }
                    }
                    else {
                        if ($userAccount.PSObject.Properties.Name -contains 'azureAdUserId') {
                            $record.UserId = [string]$userAccount.azureAdUserId
                        }
                        if ($userAccount.PSObject.Properties.Name -contains 'userPrincipalName') {
                            $record.UserPrincipalName = [string]$userAccount.userPrincipalName
                        }
                    }
                }

                if (-not $record.Contains('UserPrincipalName')) {
                    if ($sourceEntity -and $sourceEntity.PSObject.Properties.Name -contains 'UserPrincipalName') {
                        $record.UserPrincipalName = [string]$sourceEntity.UserPrincipalName
                    }
                    elseif ($sourceEntity -and $sourceEntity.PSObject.Properties.Name -contains 'DisplayName' -and [string]$sourceEntity.DisplayName -match '@') {
                        $record.UserPrincipalName = [string]$sourceEntity.DisplayName
                    }
                }
            }
            'Device' {
                if ($sourceEntity -and $sourceEntity.PSObject.Properties.Name -contains 'DeviceId') {
                    $record.DeviceId = [string]$sourceEntity.DeviceId
                }
                elseif ($sourceEntity -and $sourceEntity.PSObject.Properties.Name -contains 'MdeDeviceId') {
                    $record.DeviceId = [string]$sourceEntity.MdeDeviceId
                }
                elseif ($sourceEntity -and $sourceEntity.PSObject.Properties.Name -contains 'mdeDeviceId') {
                    $record.DeviceId = [string]$sourceEntity.mdeDeviceId
                }
            }
            'File' {
                if ($sourceEntity -and $sourceEntity.PSObject.Properties.Name -contains 'Sha256') {
                    $record.Sha256 = [string]$sourceEntity.Sha256
                }
                elseif ($sourceEntity -and $sourceEntity.PSObject.Properties.Name -contains 'fileDetails' -and $sourceEntity.fileDetails) {
                    $fileDetails = $sourceEntity.fileDetails
                    if ($fileDetails -is [System.Collections.IDictionary]) {
                        if ($fileDetails.Keys -contains 'sha256') {
                            $record.Sha256 = [string]$fileDetails['sha256']
                        }
                    }
                    elseif ($fileDetails.PSObject.Properties.Name -contains 'sha256') {
                        $record.Sha256 = [string]$fileDetails.sha256
                    }
                }
            }
        }

        return [pscustomobject]$record
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Incident.AssignedTo)) {
        $entities.Add((& $newEntityRecord -EntityType 'User' -DisplayName ([string]$Incident.AssignedTo) -AlertId $null -Source 'Incident.AssignedTo' -RawObject $null -NormalizedEntity ([pscustomobject]@{
                        UserPrincipalName = [string]$Incident.AssignedTo
                    })))
    }

    foreach ($alert in @($Alerts)) {
        $alertId = [string]$alert.AlertId
        $alertTitle = [string]$alert.Title

        if (-not [string]::IsNullOrWhiteSpace($alertTitle) -or -not [string]::IsNullOrWhiteSpace($alertId)) {
            $entities.Add((& $newEntityRecord -EntityType 'Alert' -DisplayName ($(if (-not [string]::IsNullOrWhiteSpace($alertTitle)) { $alertTitle } else { $alertId })) -AlertId $alertId -Source 'Alert' -RawObject $null -NormalizedEntity $null))
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

                                $entities.Add((& $newEntityRecord -EntityType 'Url' -DisplayName ([string]$messageUrl) -AlertId $alertId -Source 'AlertEvidence' -RawObject $rawEntity -NormalizedEntity ([pscustomobject]@{ Url = [string]$messageUrl })))
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

            $entities.Add((& $newEntityRecord -EntityType $entityType -DisplayName $displayName -AlertId $alertId -Source 'AlertEvidence' -RawObject $rawEntity -NormalizedEntity $normalizedEntity))
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
