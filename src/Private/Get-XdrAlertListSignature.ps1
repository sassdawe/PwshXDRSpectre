function Get-XdrAlertListSignature {
    <#
    .SYNOPSIS
    Builds a stable signature for an alert list.

    .DESCRIPTION
    Concatenates alert identity and visible fields into a signature string used
    to detect alert-list changes even when counts stay the same.

    .PARAMETER Alerts
    Alert collection to summarize.

    .OUTPUTS
    System.String

    .EXAMPLE
    Get-XdrAlertListSignature -Alerts $alerts
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Alerts
    )

    (@($Alerts) | ForEach-Object {
            $alertId = if ($_.PSObject.Properties['AlertId']) { [string]$_.AlertId } else { [string]$_.Id }
            "$alertId|$([string]$_.Status)|$([string]$_.Severity)|$([string]$_.Title)"
        }) -join '||'
}
