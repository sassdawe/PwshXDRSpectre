function Get-XdrActionSafetyPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ActionName,

        [Parameter()]
        [object]$Policy = (Get-XdrTriagePolicy)
    )

    return @($Policy.safetyPolicy) | Where-Object { $_.action -eq $ActionName } | Select-Object -First 1
}