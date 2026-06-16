function Test-XdrActionSafetyPolicy {
    <#
    .SYNOPSIS
    Tests whether an action requires confirmation by policy.

    .DESCRIPTION
    Looks up the configured action safety policy and returns whether the action
    is marked with the confirm safety level.

    .PARAMETER ActionName
    Display name of the action to evaluate.

    .PARAMETER Policy
    Optional preloaded triage policy object.

    .OUTPUTS
    System.Boolean

    .EXAMPLE
    Test-XdrActionSafetyPolicy -ActionName 'Clear incident assignment'
    #>
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