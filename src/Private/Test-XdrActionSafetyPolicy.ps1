function Test-XdrActionSafetyPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ActionName,

        [Parameter()]
        [object]$Policy = (Get-XdrTriagePolicy)
    )

    $entry = Get-XdrActionSafetyPolicy -ActionName $ActionName -Policy $Policy
    if (-not $entry) {
        return $false
    }

    return $entry.level -eq 'confirm'
}