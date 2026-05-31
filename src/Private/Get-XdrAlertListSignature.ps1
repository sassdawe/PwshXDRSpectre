function Get-XdrAlertListSignature {
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
