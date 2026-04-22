function New-ActionStateLine {
    <#
    .SYNOPSIS
    Builds a rendered action line for enabled or disabled state.

    .DESCRIPTION
    Keeps action labels unchanged when no disable reasons exist. If reasons are
    present, replaces the first shortcut marker with an unavailable marker.

    .PARAMETER Label
    The action label text.

    .PARAMETER Reasons
    Disable reasons for the action.

    .OUTPUTS
    System.String

    .EXAMPLE
    New-ActionStateLine -Label '(Alt+A) Assign' -Reasons @('Missing capability')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter()]
        [string[]]$Reasons
    )

    if (-not $Reasons -or $Reasons.Count -eq 0) {
        return $Label
    }

    $inactiveLabel = [regex]::Replace([string]$Label, '\((?:Alt\+)?[A-Z]\)', '(ⓧ)', 1)
    if ($inactiveLabel -eq $Label) {
        return "(ⓧ) $Label"
    }

    return $inactiveLabel
}
