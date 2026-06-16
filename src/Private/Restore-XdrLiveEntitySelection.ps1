function Restore-XdrLiveEntitySelection {
    <#
    .SYNOPSIS
    Restores entity selection from the current entity list.

    .DESCRIPTION
    Attempts to match a previously stored entity selection key against the
    current entity collection, updates selection state, and returns whether the
    original entity was restored.

    .PARAMETER Context
    Runtime context containing the current entity list.

    .PARAMETER EntitySelectionKey
    Stable entity selection key to restore.

    .PARAMETER SelectedEntity
    Reference to the selected entity object.

    .PARAMETER SelectedEntityIndex
    Reference to the selected entity index.

    .OUTPUTS
    System.Boolean

    .EXAMPLE
    Restore-XdrLiveEntitySelection -Context $context -EntitySelectionKey $pendingRefreshEntityKey -SelectedEntity ([ref]$selectedEntity) -SelectedEntityIndex ([ref]$selectedEntityIndex)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter()]
        [string]$EntitySelectionKey,

        [Parameter(Mandatory)]
        [ref]$SelectedEntity,

        [Parameter(Mandatory)]
        [ref]$SelectedEntityIndex
    )

    $entities = @($Context.Data.Entities)
    if ($entities.Count -eq 0) {
        $SelectedEntity.Value = $null
        $SelectedEntityIndex.Value = 0
        $Context.Selection.Entity = $null
        return $false
    }

    $SelectedEntityIndex.Value = 0
    if (-not [string]::IsNullOrWhiteSpace($EntitySelectionKey)) {
        for ($entityIndex = 0; $entityIndex -lt $entities.Count; $entityIndex++) {
            if ((Get-XdrEntitySelectionKey -Entity $entities[$entityIndex]) -eq $EntitySelectionKey) {
                $SelectedEntityIndex.Value = $entityIndex
                break
            }
        }
    }

    $SelectedEntity.Value = $entities[$SelectedEntityIndex.Value]
    $Context.Selection.Entity = $SelectedEntity.Value
    return ((Get-XdrEntitySelectionKey -Entity $SelectedEntity.Value) -eq $EntitySelectionKey)
}
