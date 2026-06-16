function Get-XdrAssignTargetIdentity {
    <#
    .SYNOPSIS
    Resolves the analyst identity used for incident assignment.

    .DESCRIPTION
    Returns the preferred assignable identity from the current analyst record,
    favoring mail address and then user principal name.

    .PARAMETER Context
    Runtime context containing the current analyst identity.

    .OUTPUTS
    System.String

    .EXAMPLE
    Get-XdrAssignTargetIdentity -Context $context
    #>
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