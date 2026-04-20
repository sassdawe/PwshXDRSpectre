function Get-XdrCurrentUser {
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