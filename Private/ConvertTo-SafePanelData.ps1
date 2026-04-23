function ConvertTo-SafePanelData {
    <#
    .SYNOPSIS
    Converts nullable values into non-empty panel-safe text.

    .DESCRIPTION
    Returns a single blank character when the input is null or whitespace so
    Spectre panels always receive printable content.

    .PARAMETER Value
    The value to normalize and escape.

    .OUTPUTS
    System.String

    .EXAMPLE
    ConvertTo-SafePanelData -Value $null
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ' '
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ' '
    }

    return Get-SpectreEscapedText $text
}
