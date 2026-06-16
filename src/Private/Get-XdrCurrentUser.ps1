function Get-XdrCurrentUser {
    <#
    .SYNOPSIS
    Retrieves the current Microsoft Graph user profile.

    .DESCRIPTION
    Calls Microsoft Graph for the authenticated user profile and stores the
    resolved analyst identity in runtime context when the request succeeds.

    .PARAMETER Context
    Runtime context to update with analyst identity information.

    .OUTPUTS
    System.Management.Automation.PSCustomObject

    .EXAMPLE
    Get-XdrCurrentUser -Context $context
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    $result = Invoke-XdrOperation -Operation 'Get-XdrCurrentUser' -Context $Context -ScriptBlock {
        Invoke-MgGraphRequest -Method GET -Uri '/v1.0/me' | Select-Object -Property Id, DisplayName, UserPrincipalName, Mail
    } -SuccessMessage 'Resolved current analyst identity.' -FailureMessage 'Failed to resolve current analyst identity.'

    if ($result.Success) {
        $Context.Session.Analyst = $result.Data
    }

    return $result
}