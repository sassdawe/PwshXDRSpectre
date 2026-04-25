function Get-XdrLiveHeaderPanel {
    <#
    .SYNOPSIS
    Renders the dashboard header panel.

    .DESCRIPTION
    Chooses header color based on permission health and renders either figlet
    text or a fallback markup panel for narrow terminals or figlet failures.

    .PARAMETER Context
    Runtime context object.

    .PARAMETER ScriptRoot
    Script root used to resolve figlet font path.

    .OUTPUTS
    Object

    .EXAMPLE
    Get-XdrLiveHeaderPanel -Context $context -ScriptRoot $PSScriptRoot
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )

    $headerColor = if (
        $Context.Session -and
        $Context.Session.PermissionHealth -and
        -not $Context.Session.PermissionHealth.HasSufficientWritePermissions
    ) { 'red' } else { $Context.Ui.ThemeColor }

    $fallbackMarkup = "[bold $headerColor]HELLO XDR SPECTRE[/]"

    $windowWidth = 0
    try {
        $windowWidth = [int]$Host.UI.RawUI.WindowSize.Width
    }
    catch {
        $windowWidth = 0
    }

    if ($windowWidth -gt 0 -and $windowWidth -lt 110) {
        return (Format-SpectrePanel -Data $fallbackMarkup -Expand)
    }

    try {
        return (Write-SpectreFigletText -Text 'Hello XDR Spectre' -Alignment 'Center' -Color $headerColor -FigletFontPath "$ScriptRoot/../ANSI Shadow.flf" -PassThru | Format-SpectrePanel -Expand)
    }
    catch {
        return (Format-SpectrePanel -Data $fallbackMarkup -Expand)
    }
}
