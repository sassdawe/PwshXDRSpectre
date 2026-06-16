function Set-XdrLastInputDiagnostics {
    <#
    .SYNOPSIS
    Records the most recent dashboard input diagnostics.

    .DESCRIPTION
    Stores the latest key event metadata in runtime diagnostics so input
    handling issues can be inspected from the live dashboard.

    .PARAMETER Context
    Runtime context containing diagnostics state.

    .PARAMETER Key
    Key event that was processed.

    .PARAMETER InputTime
    Timestamp when the input was observed.

    .PARAMETER KeyCharDisplay
    Display text for the key character.

    .PARAMETER ModifierSummary
    Summary of active key modifiers.

    .PARAMETER KeyHandled
    Indicates whether the key was handled.

    .PARAMETER ActivePanel
    Active logical panel when the key was processed.

    .PARAMETER IsQueryMode
    Indicates whether hunting mode was active.

    .PARAMETER SelectedQueryIndex
    Selected query index at the time of input.

    .PARAMETER SelectedQuery
    Selected query object, if any.

    .PARAMETER SelectedEntity
    Selected entity object, if any.

    .OUTPUTS
    None

    .EXAMPLE
    Set-XdrLastInputDiagnostics -Context $context -Key $key -InputTime (Get-Date) -KeyCharDisplay 'a' -ModifierSummary 'Alt' -KeyHandled $true -ActivePanel 'incident_list' -IsQueryMode $false -SelectedQueryIndex 0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [System.ConsoleKeyInfo]$Key,

        [Parameter(Mandatory)]
        [datetime]$InputTime,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$KeyCharDisplay,

        [Parameter(Mandatory)]
        [string]$ModifierSummary,

        [Parameter(Mandatory)]
        [bool]$KeyHandled,

        [Parameter(Mandatory)]
        [string]$ActivePanel,

        [Parameter(Mandatory)]
        [bool]$IsQueryMode,

        [Parameter(Mandatory)]
        [int]$SelectedQueryIndex,

        [Parameter()]
        [object]$SelectedQuery,

        [Parameter()]
        [object]$SelectedEntity
    )

    $Context.Diagnostics.LastInput = [pscustomobject][ordered]@{
        Timestamp          = $InputTime
        Key                = [string]$Key.Key
        KeyChar            = $KeyCharDisplay
        Modifiers          = $ModifierSummary
        ActivePanel        = [string]$ActivePanel
        IsQueryMode        = [bool]$IsQueryMode
        SelectedQueryIndex = [int]$SelectedQueryIndex
        SelectedQueryId    = $(if ($SelectedQuery) { [string]$SelectedQuery.id } else { '' })
        SelectedEntity     = $(if ($SelectedEntity) { [string]$SelectedEntity.DisplayName } else { '' })
        KeyHandled         = [bool]$KeyHandled
    }
}
