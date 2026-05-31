function Get-XdrEntitySelectionKey {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Entity
    )

    if (-not $Entity) {
        return ''
    }

    $parts = @(
        [string]$Entity.EntityType,
        [string]$Entity.DisplayName,
        [string]$Entity.AlertId,
        [string]$Entity.UserId,
        [string]$Entity.UserPrincipalName,
        [string]$Entity.DeviceId,
        [string]$Entity.Sha256,
        [string]$Entity.Source
    )

    return ($parts -join '|')
}
