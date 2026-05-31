function ConvertTo-XdrConsoleKeyInfo {
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