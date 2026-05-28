function New-XdrLiveDashboardLayout {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$ActionPanelVisible
    )

    $leftRatio = if ($ActionPanelVisible.IsPresent) { 2 } else { 1 }
    $centerRatio = if ($ActionPanelVisible.IsPresent) { 3 } else { 1 }
    $mainColumns = @(
        (New-SpectreLayout -Name 'left_lists' -Ratio $leftRatio -Rows @(
            (New-SpectreLayout -Name 'left_top' -Ratio 1 -Data 'empty'),
            (New-SpectreLayout -Name 'left_bottom' -Ratio 1 -Data 'empty')
        )),
        (New-SpectreLayout -Name 'center_details' -Ratio $centerRatio -Rows @(
            (New-SpectreLayout -Name 'center_top' -Ratio 1 -Data 'empty'),
            (New-SpectreLayout -Name 'center_bottom' -Ratio 1 -Data 'empty')
        ))
    )

    if ($ActionPanelVisible.IsPresent) {
        $mainColumns += (New-SpectreLayout -Name 'right_actions' -Ratio 2 -Data 'empty')
    }

    New-SpectreLayout -Name 'root' -Rows @(
        (New-SpectreLayout -Name 'main_content' -Ratio 10 -Columns $mainColumns),
        (New-SpectreLayout -Name 'help' -MinimumSize 3 -Ratio 1 -Data 'empty')
    )
}
