function ConvertTo-XdrConsoleKeyInfo {
    <#
    .SYNOPSIS
    Converts host key info into a console key record.

    .DESCRIPTION
    Projects a PowerShell host RawUI key event into System.ConsoleKeyInfo so
    the dashboard can process input consistently across key sources.

    .PARAMETER KeyInfo
    RawUI key information returned by the host.

    .OUTPUTS
    System.ConsoleKeyInfo

    .EXAMPLE
    ConvertTo-XdrConsoleKeyInfo -KeyInfo $hostKey
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Host.KeyInfo]$KeyInfo
    )

    $controlState = $KeyInfo.ControlKeyState
    $shiftPressed = (($controlState -band [System.Management.Automation.Host.ControlKeyStates]::ShiftPressed) -ne 0)
    $altPressed = (
        (($controlState -band [System.Management.Automation.Host.ControlKeyStates]::LeftAltPressed) -ne 0) -or
        (($controlState -band [System.Management.Automation.Host.ControlKeyStates]::RightAltPressed) -ne 0)
    )
    $ctrlPressed = (
        (($controlState -band [System.Management.Automation.Host.ControlKeyStates]::LeftCtrlPressed) -ne 0) -or
        (($controlState -band [System.Management.Automation.Host.ControlKeyStates]::RightCtrlPressed) -ne 0)
    )

    return [System.ConsoleKeyInfo]::new(
        [char]$KeyInfo.Character,
        [System.ConsoleKey]$KeyInfo.VirtualKeyCode,
        [bool]$shiftPressed,
        [bool]$altPressed,
        [bool]$ctrlPressed
    )
}

function Read-XdrHostKey {
    <#
    .SYNOPSIS
    Reads a pending key from the PowerShell host RawUI.

    .DESCRIPTION
    Uses the host RawUI key buffer as a fallback input source when direct
    console reads are unavailable or insufficient.

    .OUTPUTS
    System.ConsoleKeyInfo

    .EXAMPLE
    Read-XdrHostKey
    #>
    [CmdletBinding()]
    param()

    try {
        if ($Host -and $Host.UI -and $Host.UI.RawUI -and $Host.UI.RawUI.KeyAvailable) {
            $hostKey = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]'NoEcho,IncludeKeyDown')
            if ($hostKey) {
                return ConvertTo-XdrConsoleKeyInfo -KeyInfo $hostKey
            }
        }
    }
    catch {
        return $null
    }

    return $null
}

function Get-XdrLastKeyPressed {
    <#
    .SYNOPSIS
    Returns the most recent pending key press.

    .DESCRIPTION
    Drains both the console and host RawUI key buffers and returns the last key
    observed so the dashboard handles the freshest input state.

    .OUTPUTS
    System.ConsoleKeyInfo

    .EXAMPLE
    Get-XdrLastKeyPressed
    #>
    [CmdletBinding()]
    param()

    $lastKeyPressed = $null
    try {
        while ([Console]::KeyAvailable) {
            $lastKeyPressed = [Console]::ReadKey($true)
        }
    }
    catch {
        $lastKeyPressed = $null
    }

    $hostKeyPressed = Read-XdrHostKey
    while ($null -ne $hostKeyPressed) {
        $lastKeyPressed = $hostKeyPressed
        $hostKeyPressed = Read-XdrHostKey
    }

    return $lastKeyPressed
}

function Get-XdrAllKeysPressed {
    <#
    .SYNOPSIS
    Returns all pending key presses.

    .DESCRIPTION
    Drains both the console and host RawUI key buffers and returns every queued
    key event for bulk input processing or diagnostics.

    .OUTPUTS
    System.ConsoleKeyInfo[]

    .EXAMPLE
    Get-XdrAllKeysPressed
    #>
    [CmdletBinding()]
    param()

    $allKeys = [System.Collections.Generic.List[System.ConsoleKeyInfo]]::new()
    try {
        while ([Console]::KeyAvailable) {
            [void]$allKeys.Add([Console]::ReadKey($true))
        }
    }
    catch {
    }

    $hostKeyPressed = Read-XdrHostKey
    while ($null -ne $hostKeyPressed) {
        [void]$allKeys.Add($hostKeyPressed)
        $hostKeyPressed = Read-XdrHostKey
    }

    return $allKeys.ToArray()
}