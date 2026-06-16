function Resolve-XdrQueryParameters {
    <#
    .SYNOPSIS
    Resolves query parameters from the current dashboard context.

    .DESCRIPTION
    Maps query parameter bindings to the currently selected incident or entity,
    applies default values when present, and reports any required context that
    is still missing.

    .PARAMETER Query
    Query definition containing parameter metadata.

    .PARAMETER Context
    Runtime context containing current selections.

    .OUTPUTS
    System.Management.Automation.PSCustomObject

    .EXAMPLE
    Resolve-XdrQueryParameters -Query $selectedQuery -Context $context
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Query,

        [Parameter(Mandatory)]
        [object]$Context
    )

    $resolvedParameters = [ordered]@{}
    $missingContext = New-Object System.Collections.Generic.List[string]
    $requiredContext = @($Query.requiredContext | ForEach-Object { [string]$_ })

    $getEntityValue = {
        param(
            [object]$Entity,
            [string[]]$PropertyNames,
            [scriptblock]$RawResolver = $null
        )

        if ($Entity) {
            foreach ($propertyName in $PropertyNames) {
                if ($Entity.PSObject.Properties.Name -contains $propertyName) {
                    $candidateValue = [string]$Entity.$propertyName
                    if (-not [string]::IsNullOrWhiteSpace($candidateValue)) {
                        return $candidateValue
                    }
                }
            }

            if ($RawResolver -and $Entity.PSObject.Properties.Name -contains 'RawObject' -and $Entity.RawObject) {
                $rawValue = & $RawResolver $Entity.RawObject
                if (-not [string]::IsNullOrWhiteSpace([string]$rawValue)) {
                    return [string]$rawValue
                }
            }
        }

        return $null
    }

    foreach ($parameter in @($Query.parameters)) {
        $parameterName = [string]$parameter.name
        $contextBinding = [string]$parameter.contextBinding
        $value = $null

        switch ($contextBinding) {
            'IncidentId' {
                if ($Context.Selection.Incident -and $Context.Selection.Incident.PSObject.Properties.Name -contains 'IncidentId') {
                    $value = [string]$Context.Selection.Incident.IncidentId
                }
            }
            'DeviceId' {
                $value = & $getEntityValue $Context.Selection.Entity @('DeviceId', 'MdeDeviceId', 'mdeDeviceId') {
                    param($rawEntity)
                    if ($rawEntity.PSObject.Properties.Name -contains 'AdditionalProperties' -and $rawEntity.AdditionalProperties) {
                        $rawEntity = [pscustomobject][hashtable]$rawEntity.AdditionalProperties
                    }

                    if ($rawEntity.PSObject.Properties.Name -contains 'mdeDeviceId') {
                        return [string]$rawEntity.mdeDeviceId
                    }

                    return $null
                }
            }
            'UserId' {
                $value = & $getEntityValue $Context.Selection.Entity @('UserId', 'AzureAdUserId', 'AadUserId') {
                    param($rawEntity)
                    if ($rawEntity.PSObject.Properties.Name -contains 'AdditionalProperties' -and $rawEntity.AdditionalProperties) {
                        $rawEntity = [pscustomobject][hashtable]$rawEntity.AdditionalProperties
                    }

                    if ($rawEntity.PSObject.Properties.Name -contains 'userAccount' -and $rawEntity.userAccount) {
                        $userAccount = $rawEntity.userAccount
                        if ($userAccount -is [System.Collections.IDictionary] -and $userAccount.Keys -contains 'azureAdUserId') {
                            return [string]$userAccount['azureAdUserId']
                        }

                        if ($userAccount.PSObject.Properties.Name -contains 'azureAdUserId') {
                            return [string]$userAccount.azureAdUserId
                        }
                    }

                    return $null
                }
            }
            'FileHash' {
                $value = & $getEntityValue $Context.Selection.Entity @('Sha256') {
                    param($rawEntity)
                    if ($rawEntity.PSObject.Properties.Name -contains 'AdditionalProperties' -and $rawEntity.AdditionalProperties) {
                        $rawEntity = [pscustomobject][hashtable]$rawEntity.AdditionalProperties
                    }

                    if ($rawEntity.PSObject.Properties.Name -contains 'fileDetails' -and $rawEntity.fileDetails) {
                        $fileDetails = $rawEntity.fileDetails
                        if ($fileDetails -is [System.Collections.IDictionary] -and $fileDetails.Keys -contains 'sha256') {
                            return [string]$fileDetails['sha256']
                        }

                        if ($fileDetails.PSObject.Properties.Name -contains 'sha256') {
                            return [string]$fileDetails.sha256
                        }
                    }

                    return $null
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($value) -and $parameter.PSObject.Properties.Name -contains 'defaultValue') {
            $value = [string]$parameter.defaultValue
        }

        if ([string]::IsNullOrWhiteSpace($value) -and -not [string]::IsNullOrWhiteSpace($contextBinding) -and $requiredContext -contains $contextBinding) {
            $missingContext.Add($contextBinding)
        }

        $resolvedParameters[$parameterName] = $value
    }

    $distinctMissingContext = @($missingContext | Select-Object -Unique)

    return [pscustomobject]@{
        Success        = $distinctMissingContext.Count -eq 0
        IsBlocked      = $distinctMissingContext.Count -gt 0
        Parameters     = $resolvedParameters
        MissingContext = $distinctMissingContext
        Message        = $(if ($distinctMissingContext.Count -gt 0) {
                "Missing required query context: $($distinctMissingContext -join ', ')"
            }
            else {
                'Resolved query parameters successfully.'
            })
    }
}