function Get-XdrAssignTargetIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    if (-not $Context.Session -or -not $Context.Session.Analyst) {
        return $null
    }

    if (-not [string]::IsNullOrWhiteSpace($Context.Session.Analyst.Mail)) {
        return $Context.Session.Analyst.Mail
    }

    if (-not [string]::IsNullOrWhiteSpace($Context.Session.Analyst.UserPrincipalName)) {
        return $Context.Session.Analyst.UserPrincipalName
    }

    return $null
}