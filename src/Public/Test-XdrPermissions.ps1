function Test-XdrPermissions {
    <#
        .SYNOPSIS
        Validates Defender XDR permission level for the current Graph session.

        .DESCRIPTION
        Reads Microsoft Graph delegated scopes from the active Graph context and
        determines whether the current session has Defender XDR Reader access,
        Operator access, or neither. When a runtime context is supplied, the
        function also refreshes Context.Session.PermissionHealth using the
        existing module permission-health detector.

        .PARAMETER Context
        Optional runtime context object created by New-XdrRuntimeContext.

        .OUTPUTS
        PSCustomObject containing Success, Operation, Message, Data, Error,
        and Metadata properties.

        .EXAMPLE
        Test-XdrPermissions

        .EXAMPLE
        Test-XdrPermissions -Context $ctx

        .NOTES
        Access levels are determined from Graph delegated scopes:
        - Operator: SecurityIncident.ReadWrite.All
        - Reader: SecurityIncident.Read.All (or SecurityIncident.ReadWrite.All)
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Context
    )

    $operationName = 'Test-XdrPermissions'

    $graphContext = $null
    try {
        $graphContext = Get-MgContext
    }
    catch {
        return [pscustomobject]@{
            Success   = $false
            Operation = $operationName
            Message   = 'No active Microsoft Graph context was found. Connect first using Connect-XdrSession.'
            Data      = [pscustomobject]@{
                AccessLevel         = 'None'
                HasReaderAccess     = $false
                HasOperatorAccess   = $false
                AvailableScopes     = @()
                MissingScopes       = @('SecurityIncident.Read.All')
                IsConnectedToGraph  = $false
            }
            Error     = $_.Exception
            Metadata  = $null
        }
    }

    if ($null -eq $graphContext -or [string]::IsNullOrWhiteSpace([string]$graphContext.TenantId)) {
        return [pscustomobject]@{
            Success   = $false
            Operation = $operationName
            Message   = 'No active Microsoft Graph context was found. Connect first using Connect-XdrSession.'
            Data      = [pscustomobject]@{
                AccessLevel         = 'None'
                HasReaderAccess     = $false
                HasOperatorAccess   = $false
                AvailableScopes     = @()
                MissingScopes       = @('SecurityIncident.Read.All')
                IsConnectedToGraph  = $false
            }
            Error     = $null
            Metadata  = $null
        }
    }

    $availableScopes = @()
    if ($graphContext -and $graphContext.Scopes) {
        $availableScopes = @(
            $graphContext.Scopes |
                ForEach-Object { ([string]$_).Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
        )
    }

    $normalizedScopes = @($availableScopes | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $hasIncidentReadScope = ($normalizedScopes -contains 'securityincident.read.all')
    $hasIncidentWriteScope = ($normalizedScopes -contains 'securityincident.readwrite.all')

    $hasReaderAccess = ($hasIncidentReadScope -or $hasIncidentWriteScope)
    $hasOperatorAccess = $hasIncidentWriteScope

    $accessLevel = if ($hasOperatorAccess) {
        'Operator'
    }
    elseif ($hasReaderAccess) {
        'Reader'
    }
    else {
        'None'
    }

    $requiredReaderScopes = @('SecurityIncident.Read.All')
    $missingScopes = @()
    if (-not $hasReaderAccess) {
        $missingScopes = $requiredReaderScopes
    }

    if ($null -ne $Context) {
        Set-ContextPermissionHealthFromGraphContext -RuntimeContext $Context
    }

    $isConnected = ($null -ne $graphContext -and -not [string]::IsNullOrWhiteSpace([string]$graphContext.TenantId))
    $resultData = [pscustomobject]@{
        AccessLevel        = $accessLevel
        HasReaderAccess    = $hasReaderAccess
        HasOperatorAccess  = $hasOperatorAccess
        AvailableScopes    = $availableScopes
        MissingScopes      = $missingScopes
        IsConnectedToGraph = $isConnected
    }

    $resultMessage = if ($hasOperatorAccess) {
        'Operator access validated (SecurityIncident.ReadWrite.All present).'
    }
    elseif ($hasReaderAccess) {
        'Reader access validated (SecurityIncident.Read.All present).'
    }
    else {
        'Reader or Operator access is missing. Request SecurityIncident.Read.All (Reader) or SecurityIncident.ReadWrite.All (Operator).'
    }

    return [pscustomobject]@{
        Success   = $hasReaderAccess
        Operation = $operationName
        Message   = $resultMessage
        Data      = $resultData
        Error     = $null
        Metadata  = $null
    }
}