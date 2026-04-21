function Connect-XdrSession {
    [CmdletBinding()]
    param(
        # Bring your own context object.
        [Parameter(Mandatory, ParameterSetName = 'Context')]
        [object]$Context,
        # Bring your own ClientID
        [Parameter(Mandatory, ParameterSetName = 'ClientId')]
        [System.String]$ClientId,
        # Bring your own TenantId
        [Parameter(Mandatory, ParameterSetName = 'ClientId')]
        [System.String]$TenantId,
        # Use device code for authentication
        [Parameter(Mandatory = $false)]
        [switch]$UseDeviceCode
    )

    $PSDefaultParameterValues['Connect-MgGraph:NoWelcome'] = $true

    # if the paramater is Contect, we'll Connect using the details in the context, otherwise we'll use the ClientId and TenantId parameters
    if ($PSBoundParameters.ContainsKey('Context')) { 
        $connectResult = Invoke-XdrOperation -Operation 'Connect-XdrSession' -Context $Context -ScriptBlock {
            Connect-MgGraph -TenantId $Context.Session.TenantId -ClientId $Context.Session.ClientId -ContextScope CurrentUser -NoWelcome:$true -UseDeviceCode:$UseDeviceCode.IsPresent
        } -SuccessMessage 'Connected to Microsoft Graph.' -FailureMessage 'Could not connect to Microsoft Graph.'

        if (-not $connectResult.Success) {
            $Context.Session.IsConnected = $false
            return $connectResult
        }

        $whoAmI = Get-XdrCurrentUser -Context $Context
        if (-not $whoAmI.Success) {
            $Context.Session.IsConnected = $false
            return $whoAmI
        }
        $Context.Session.IsConnected = $true
        $Context.Capabilities.IncidentActions = @(
            'AssignIncident',
            'ClearIncidentAssignment',
            'UpdateIncidentStatus',
            'UpdateIncidentClassification',
            'UpdateIncidentDetermination'
        )
        $Context.Capabilities.AlertActions = @('GetAlerts', 'UpdateAlertStatus')

    }
    else {
        $connectResult = Invoke-XdrOperation -Operation 'Connect-XdrSession' -Context $Context -ScriptBlock {
            Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -ContextScope CurrentUser -NoWelcome:$true -UseDeviceCode:$UseDeviceCode.IsPresent
        } -SuccessMessage 'Connected to Microsoft Graph.' -FailureMessage 'Could not connect to Microsoft Graph.'

        if (-not $connectResult.Success) {
            return $connectResult
        }
        $Context.Session.IsConnected = $true
        # Update the context with the new session details
        $Context.Session.ClientId = $ClientId
        $Context.Session.TenantId = $TenantId

        $whoAmI = Get-XdrCurrentUser -Context $Context
        if (-not $whoAmI.Success) {
            return $whoAmI
        }

        $Context.Capabilities.IncidentActions = @(
            'AssignIncident',
            'ClearIncidentAssignment',
            'UpdateIncidentStatus',
            'UpdateIncidentClassification',
            'UpdateIncidentDetermination'
        )
        $Context.Capabilities.AlertActions = @('GetAlerts', 'UpdateAlertStatus')
    }
    
    return $connectResult
}