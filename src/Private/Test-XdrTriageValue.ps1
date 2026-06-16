function Test-XdrTriageValue {
    <#
    .SYNOPSIS
    Tests whether a display value exists in a triage policy map.

    .DESCRIPTION
    Checks the requested triage policy map for a matching display label and
    returns whether that label is defined.

    .PARAMETER MapName
    Policy map name to query.

    .PARAMETER DisplayValue
    Display label to look up.

    .PARAMETER Policy
    Optional preloaded triage policy object.

    .OUTPUTS
    System.Boolean

    .EXAMPLE
    Test-XdrTriageValue -MapName 'incidentStatusMap' -DisplayValue 'Resolved'
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

    $map = @($Policy.$MapName)
    if (-not $map) {
        return $false
    }

    return $null -ne ($map | Where-Object { $_.label -eq $DisplayValue } | Select-Object -First 1)
}