function Get-XdrLastKeyPressed {
    [CmdletBinding()]
    param()

    $lastKeyPressed = $null
    while ([Console]::KeyAvailable) {
        $lastKeyPressed = [Console]::ReadKey($true)
    }

    return $lastKeyPressed
}

function Get-XdrAllKeysPressed {
    [CmdletBinding()]
    param()

    $allKeys = [System.Collections.Generic.List[System.ConsoleKeyInfo]]::new()
    while ([Console]::KeyAvailable) {
        [void]$allKeys.Add([Console]::ReadKey($true))
    }

    return $allKeys.ToArray()
}