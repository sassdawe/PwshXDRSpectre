function Get-XdrLiveTabOrder {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$ExperimentalFeaturesEnabled
    )

    $tabOrder = @('welcome', 'incidents', 'hunting', 'query_library', 'quarantine')

    if ($ExperimentalFeaturesEnabled.IsPresent) {
        $tabOrder += 'live_investigation'
    }

    $tabOrder += @('action_center', 'settings', 'help')
    return @($tabOrder)
}
