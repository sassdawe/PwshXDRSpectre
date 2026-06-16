function Resolve-XdrGraphEnumValue {
    <#
    .SYNOPSIS
    Resolves a display label to its Microsoft Graph enum value.

    .DESCRIPTION
    Looks up the requested label in the configured triage policy map and returns
    the corresponding Graph enum string.

    .PARAMETER MapName
    Policy map name to query.

    .PARAMETER DisplayValue
    Display label to resolve.

    .PARAMETER Policy
    Optional preloaded triage policy object.

    .OUTPUTS
    System.String

    .EXAMPLE
    Resolve-XdrGraphEnumValue -MapName 'incidentStatusMap' -DisplayValue 'Resolved'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MapName,

        [Parameter(Mandatory)]
        [string]$DisplayValue,

        [Parameter()]
        [object]$Policy = (Get-XdrTriagePolicy)
    )

    $match = @($Policy.$MapName) | Where-Object { $_.label -eq $DisplayValue } | Select-Object -First 1
    if (-not $match) {
        throw "Unknown triage value '$DisplayValue' for map '$MapName'"
    }

    return $match.graphValue
}