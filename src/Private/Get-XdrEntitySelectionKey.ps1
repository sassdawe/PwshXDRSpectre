function Get-XdrEntitySelectionKey {
    <#
    .SYNOPSIS
    Builds a stable selection key for an entity.

    .DESCRIPTION
    Concatenates the identifying properties used to preserve or restore entity
    selection across refreshes and panel rebinds.

    .PARAMETER Entity
    Entity object to summarize.

    .OUTPUTS
    System.String

    .EXAMPLE
    Get-XdrEntitySelectionKey -Entity $selectedEntity
    #>
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
