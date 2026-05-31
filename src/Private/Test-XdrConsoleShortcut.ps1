function Test-XdrConsoleShortcut {
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
