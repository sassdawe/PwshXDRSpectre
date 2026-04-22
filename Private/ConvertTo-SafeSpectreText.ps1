function ConvertTo-SafeSpectreText {
    <#
    .SYNOPSIS
    Converts nullable values into Spectre-safe text.

    .DESCRIPTION
    Returns an empty string when the input is null or whitespace. Otherwise,
    escapes markup characters for safe rendering in Spectre panels.

    .PARAMETER Value
    The value to normalize and escape.

    .OUTPUTS
    System.String

    .EXAMPLE
    ConvertTo-SafeSpectreText -Value 'alpha [beta]'
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ''
    }

    return Get-SpectreEscapedText $text
}
