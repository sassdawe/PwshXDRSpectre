function Connect-XdrSession {
    <#
        .SYNOPSIS
        Establishes an authenticated session with Microsoft Defender XDR via Microsoft Graph.

        .DESCRIPTION
        Connects to Microsoft Graph using either an existing runtime context object or a
        ClientId / TenantId pair. After authentication, inspects the granted Graph scopes
        and stores permission health information on the context so the rest of the module
        can enforce capability guards at runtime.

        .PARAMETER Context
        A runtime context object created by New-XdrRuntimeContext. When supplied the
        function uses the TenantId and ClientId already stored inside the context.

        .PARAMETER ClientId
        The Azure AD application (client) ID to use for authentication.
        Required when not providing a pre-built Context object.

        .PARAMETER TenantId
        The Azure AD tenant ID for the target organization.
        Required when not providing a pre-built Context object.

        .PARAMETER UseDeviceCode
        When specified, uses device code flow for interactive authentication instead of
        the default browser-based interactive flow.

        .OUTPUTS
        PSCustomObject containing Success, Operation, Message, Data, Error, and Metadata
        properties. The returned object follows the standard XDR operation result shape.

        .EXAMPLE
        $ctx = New-XdrRuntimeContext -TenantId 'xxxxxxxx-...' -ClientId 'yyyyyyyy-...'
        Connect-XdrSession -Context $ctx

        .EXAMPLE
        Connect-XdrSession -TenantId 'xxxxxxxx-...' -ClientId 'yyyyyyyy-...' -UseDeviceCode

        .NOTES
        Requires the Microsoft.Graph PowerShell SDK. The SecurityIncident.ReadWrite.All
        Graph permission is needed for full write capabilities; without it the session
        is placed in read-only mode.
    #>
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

        $hasIncidentWriteScope = ($availableScopes -contains 'SecurityIncident.ReadWrite.All')

        if ($availableScopes.Count -gt 0 -and -not $hasIncidentWriteScope) {
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