function Get-XdrIncidentDetailsTabHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrentTab
    )

    if ([string]$CurrentTab -eq 'entities') {
        return '[grey70 on #1C1C1C]| Incident details |[/][bold black on #C0C0C0]| Entities |[/] [grey](ALT+D to switch)[/]'
    }

    return '[bold black on #C0C0C0]| Incident details |[/][grey70 on #1C1C1C]| Entities |[/] [grey](ALT+E to switch)[/]'
}
