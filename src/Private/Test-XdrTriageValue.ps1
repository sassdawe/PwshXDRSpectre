function Test-XdrTriageValue {
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