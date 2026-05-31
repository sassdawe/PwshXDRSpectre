function Set-XdrLastInputDiagnostics {
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
