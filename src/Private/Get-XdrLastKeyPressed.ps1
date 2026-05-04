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

    $allKeys = @()
    while ([Console]::KeyAvailable) {
        $allKeys += [Console]::ReadKey($true)
    }

    return $allKeys
}