function Invoke-XdrQueryInterpolation {
    <#
    .SYNOPSIS
    Interpolates resolved parameters into a hunting query.

    .DESCRIPTION
    Validates each resolved parameter for presence and safe format, then
    substitutes the parameter values into the query KQL text.

    .PARAMETER Query
    Query definition containing parameter metadata and KQL.

    .PARAMETER Parameters
    Resolved parameter values keyed by parameter name.

    .OUTPUTS
    System.Management.Automation.PSCustomObject

    .EXAMPLE
    Invoke-XdrQueryInterpolation -Query $query -Parameters @{ IncidentId = '1234' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Query,

        [Parameter(Mandatory)]
        [hashtable]$Parameters
    )

    $interpolatedKql = [string]$Query.kql
    foreach ($parameterDefinition in @($Query.parameters)) {
        $parameterName = [string]$parameterDefinition.name
        if (-not $Parameters.Contains($parameterName)) {
            throw "Cannot interpolate query '$([string]$Query.id)': Missing resolved parameter '$parameterName'."
        }

        $parameterValue = [string]$Parameters[$parameterName]
        if ([string]::IsNullOrWhiteSpace($parameterValue)) {
            throw "Cannot interpolate query '$([string]$Query.id)': Parameter '$parameterName' resolved to an empty value."
        }

        $contextBinding = [string]$parameterDefinition.contextBinding
        switch ($contextBinding) {
            'IncidentId' {
                if ($parameterValue -notmatch '^[A-Za-z0-9-]+$') {
                    throw "Unsafe IncidentId value for query '$([string]$Query.id)'."
                }
            }
            'DeviceId' {
                if ($parameterValue -notmatch '^[A-Za-z0-9-]+$') {
                    throw "Unsafe DeviceId value for query '$([string]$Query.id)'."
                }
            }
            'UserId' {
                if ($parameterValue -notmatch '^[A-Za-z0-9-]+$') {
                    throw "Unsafe UserId value for query '$([string]$Query.id)'."
                }
            }
            'FileHash' {
                if ($parameterValue -notmatch '^[A-Za-z0-9]+$') {
                    throw "Unsafe FileHash value for query '$([string]$Query.id)'."
                }
            }
        }

        $interpolatedKql = $interpolatedKql -replace "\{\{\s*$([regex]::Escape($parameterName))\s*\}\}", $parameterValue
    }

    return [pscustomobject]@{
        Success    = $true
        QueryId    = [string]$Query.id
        Kql        = $interpolatedKql
        Parameters = $Parameters
    }
}