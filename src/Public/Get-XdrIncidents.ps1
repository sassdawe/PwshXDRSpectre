function Get-XdrIncidents {
    <#
        .SYNOPSIS
        Retrieves Microsoft Defender XDR incidents and converts them to view models.

        .DESCRIPTION
        Fetches incidents from the Microsoft Graph Security API, optionally limiting the
        result count, converts each incident to a normalized XDR incident view model,
        and stores the result on the runtime context. The context cache is updated with
        the retrieved incidents and a LastRefresh timestamp.

        .PARAMETER Context
        The runtime context object. Retrieved incidents are stored in Context.Data.Incidents.

        .PARAMETER Limit
        Maximum number of incidents to return. When 0 or not specified, all incidents
        are retrieved.

        .OUTPUTS
        PSCustomObject containing Success, Operation, Message, Data (array of incident
        view models), Error, and Metadata properties.

        .EXAMPLE
        $result = Get-XdrIncidents -Context $ctx

        .EXAMPLE
        $result = Get-XdrIncidents -Context $ctx -Limit 25

        .NOTES
        Requires a connected session with at least SecurityIncident.Read.All permissions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter()]
        [int]$Limit
    )

    $operationResult = Invoke-XdrOperation -Operation 'Get-XdrIncidents' -Context $Context -ScriptBlock {
        if ($Limit -gt 0) {
            Get-MgSecurityIncident | Select-Object -First $Limit
        }
        else {
            Get-MgSecurityIncident
        }
    } -SuccessMessage 'Retrieved incidents successfully.' -FailureMessage 'Failed to retrieve incidents.'

    if (-not $operationResult.Success) {
        return $operationResult
    }

    $tenantId = $Context.Session.TenantId
    $viewModels = @($operationResult.Data | ForEach-Object { ConvertTo-XdrIncidentViewModel -Incident $_ -TenantId $tenantId })
    $Context.Data.Incidents = $viewModels
    $Context.Data.LastRefresh = Get-Date

    return [pscustomobject]@{
        Success   = $true
        Operation = 'Get-XdrIncidents'
        Message   = "Retrieved $($viewModels.Count) incident(s)."
        Data      = $viewModels
        Error     = $null
        Metadata  = $operationResult.Metadata
    }
}