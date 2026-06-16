function Test-XdrConsoleShortcut {
    <#
    .SYNOPSIS
    Tests whether a key event matches a shortcut definition.

    .DESCRIPTION
    Compares the physical key and requested modifier flags against a console
    key event to determine whether a shortcut was triggered.

    .PARAMETER Key
    Key event to evaluate.

    .PARAMETER KeyName
    Expected key name.

    .PARAMETER Alt
    Requires the Alt modifier when set.

    .PARAMETER Control
    Requires the Control modifier when set.

    .PARAMETER Shift
    Requires the Shift modifier when set.

    .OUTPUTS
    System.Boolean

    .EXAMPLE
    Test-XdrConsoleShortcut -Key $key -KeyName 'H' -Alt
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.ConsoleKeyInfo]$Key,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$KeyName,

        [Parameter()]
        [switch]$Alt,

        [Parameter()]
        [switch]$Control,

        [Parameter()]
        [switch]$Shift
    )

    $expectedKeyName = $KeyName.ToLowerInvariant()
    $keyNameMatches = ([string]$Key.Key).ToLowerInvariant() -eq $expectedKeyName
    $keyCharMatches = $Key.KeyChar -and -not [char]::IsControl($Key.KeyChar) -and ([string]$Key.KeyChar).ToLowerInvariant() -eq $expectedKeyName
    if (-not ($keyNameMatches -or $keyCharMatches)) {
        return $false
    }

    $altPressed = (($Key.Modifiers -band [ConsoleModifiers]::Alt) -ne 0)
    $controlPressed = (($Key.Modifiers -band [ConsoleModifiers]::Control) -ne 0)
    $shiftPressed = (($Key.Modifiers -band [ConsoleModifiers]::Shift) -ne 0)

    return (
        $altPressed -eq $Alt.IsPresent -and
        $controlPressed -eq $Control.IsPresent -and
        $shiftPressed -eq $Shift.IsPresent
    )
}
