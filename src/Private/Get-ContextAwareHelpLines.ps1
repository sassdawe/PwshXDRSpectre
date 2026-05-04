function Get-ContextAwareHelpLines {
    <#
    .SYNOPSIS
    Returns keyboard help lines based on current dashboard state.

    .DESCRIPTION
    Produces concise contextual guidance for the active panel and modal states
    such as confirmation prompts, text input, or incident resolution workflow.

    .PARAMETER ActivePanel
    The currently active panel.

    .PARAMETER SelectedIncident
    Selected incident object.

    .PARAMETER SelectedAlert
    Selected alert object.

    .PARAMETER PendingConfirmation
    Current confirmation payload.

    .PARAMETER PendingTextInput
    Current text input payload.

    .PARAMETER PendingIncidentResolution
    Current incident resolution workflow payload.

    .PARAMETER PendingIncidentClassification
    Current incident classification workflow payload.

    .PARAMETER PendingIncidentComment
    Current incident comment workflow payload.

    .OUTPUTS
    System.String[]

    .EXAMPLE
    Get-ContextAwareHelpLines -ActivePanel incidents
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ActivePanel,

        [Parameter()]
        [object]$SelectedIncident,

        [Parameter()]
        [object]$SelectedAlert,

        [Parameter()]
        [object]$PendingConfirmation,

        [Parameter()]
        [object]$PendingTextInput,

        [Parameter()]
        [object]$PendingIncidentResolution,

        [Parameter()]
        [object]$PendingIncidentClassification,

        [Parameter()]
        [object]$PendingIncidentComment
    )

    if ($null -ne $PendingIncidentResolution) {
        return @('Incident resolution wizard active | Enter next page | PgUp/PgDn back/next | Y submit on final page | Esc cancel')
    }

    if ($null -ne $PendingIncidentClassification) {
        return @('Incident classification wizard active | Enter next page | PgUp back | Y submit on final page | Esc cancel')
    }

    if ($null -ne $PendingIncidentComment) {
        return @('Incident comment wizard active | Type comment | Enter next page | PgUp back | Y submit on final page | Esc cancel')
    }

    if ($null -ne $PendingTextInput) {
        return @('Comment input mode | Type text | Enter submit | Backspace edit | Esc cancel | Shortcuts disabled')
    }

    $baseLine = 'Alt+A/U/O/I/R/K/C incident | Alt+L load alerts | Alt+N/P/M alert | F5 refresh | Tab/Shift+Tab or PgUp/PgDn switch | ↑/↓ move | Enter run/load'

    switch ($ActivePanel) {
        'incidents' { return @('↑/↓ incidents | Enter or L loads alerts | F5 refresh incidents | Tab or PgUp/PgDn switch') }
        'incident_details' { return @('Alt+A/U/O/I/R/K/C selected incident | Alt+L or Enter loads alerts | Tab or PgUp/PgDn switch') }
        'alerts' { return @('↑/↓ alerts | Alt+N/P/M selected alert | F5 refresh incidents | Tab or PgUp/PgDn switch') }
        'alert_details' { return @('Alt+N/P/M selected alert | Load alerts with Alt+L/Enter if needed | Tab or PgUp/PgDn switch') }
        'action_status' { return @('↑/↓ select action | Enter execute selected | Alt+A/U/O/I/R/K/C/L/N/P/M shortcuts | F5 refresh incidents | Tab or PgUp/PgDn switch') }
    }

    return @($baseLine)
}
