function Get-XdrLastKeyPressed {
    [CmdletBinding()]
    param()

    $lastKeyPressed = $null
    while ([Console]::KeyAvailable) {
        $lastKeyPressed = [Console]::ReadKey($true)
    }

    return $lastKeyPressed
}