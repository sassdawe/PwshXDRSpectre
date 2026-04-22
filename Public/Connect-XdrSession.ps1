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

    function Set-ContextPermissionHealthFromGraphContext {
        param(
            [Parameter(Mandatory)]
            [object]$RuntimeContext
        )

        if (-not $RuntimeContext -or -not $RuntimeContext.Session) {
            return
        }

        $graphContext = $null
        try {
            $graphContext = Get-MgContext
        }
        catch {
            $graphContext = $null
        }

        $availableScopes = @()
        if ($graphContext -and $graphContext.Scopes) {
            $availableScopes = @($graphContext.Scopes | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        }

        if (-not $RuntimeContext.Session.PSObject.Properties.Name.Contains('PermissionHealth')) {
            $RuntimeContext.Session | Add-Member -MemberType NoteProperty -Name PermissionHealth -Value ([pscustomobject][ordered]@{
                    HasSufficientWritePermissions = $true
                    DetectionSource               = 'default'
                    RequiredPermissions           = @()
                    AvailablePermissions          = @()
                    LastUpdatedAt                 = $null
                })
        }

        $RuntimeContext.Session.PermissionHealth.AvailablePermissions = $availableScopes
        $RuntimeContext.Session.PermissionHealth.LastUpdatedAt = Get-Date

        if ($availableScopes.Count -gt 0 -and -not ($availableScopes -contains 'SecurityIncident.ReadWrite.All')) {
            $RuntimeContext.Session.PermissionHealth.HasSufficientWritePermissions = $false
            $RuntimeContext.Session.PermissionHealth.DetectionSource = 'graph-scope'
            $RuntimeContext.Session.PermissionHealth.RequiredPermissions = @('SecurityIncident.ReadWrite.All')
            $RuntimeContext.Capabilities.IncidentActions = @()
            $RuntimeContext.Capabilities.AlertActions = @('GetAlerts')
        }
        else {
            $RuntimeContext.Session.PermissionHealth.HasSufficientWritePermissions = $true
            $RuntimeContext.Session.PermissionHealth.DetectionSource = 'graph-scope'
            $RuntimeContext.Session.PermissionHealth.RequiredPermissions = @()
        }
    }

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
        Set-ContextPermissionHealthFromGraphContext -RuntimeContext $Context

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
        Set-ContextPermissionHealthFromGraphContext -RuntimeContext $Context
    }
    
    return $connectResult
}