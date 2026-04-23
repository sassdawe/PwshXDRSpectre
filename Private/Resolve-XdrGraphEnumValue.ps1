function Resolve-XdrGraphEnumValue {
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