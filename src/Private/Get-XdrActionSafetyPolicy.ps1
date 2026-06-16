function Get-XdrActionSafetyPolicy {
    <#
    .SYNOPSIS
    Returns the configured safety policy for an action.

    .DESCRIPTION
    Looks up the matching safety-policy entry for the supplied action name from
    the triage policy configuration.

    .PARAMETER ActionName
    Display name of the action to evaluate.

    .PARAMETER Policy
    Optional preloaded triage policy object.

    .OUTPUTS
    System.Object

    .EXAMPLE
    Get-XdrActionSafetyPolicy -ActionName 'Assign incident to me'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ActionName,

        [Parameter()]
        [object]$Policy = (Get-XdrTriagePolicy)
    )

    return @($Policy.safetyPolicy) | Where-Object { $_.action -eq $ActionName } | Select-Object -First 1
}