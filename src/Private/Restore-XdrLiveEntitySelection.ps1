function Restore-XdrLiveEntitySelection {
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
