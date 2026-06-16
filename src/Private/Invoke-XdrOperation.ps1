function Invoke-XdrOperation {
    <#
    .SYNOPSIS
    Executes an XDR operation inside a standard result envelope.

    .DESCRIPTION
    Runs the supplied script block, captures duration, normalizes success or
    failure output, and updates runtime permission health when Graph errors
    indicate missing write scopes.

    .PARAMETER Operation
    Logical operation name used in result and error records.

    .PARAMETER ScriptBlock
    Operation implementation to execute.

    .PARAMETER Context
    Optional runtime context updated with permission-health metadata.

    .PARAMETER SuccessMessage
    Optional success message for the result envelope.

    .PARAMETER FailureMessage
    Optional failure message for the result envelope.

    .PARAMETER TargetObject
    Optional target object associated with the operation.

    .OUTPUTS
    System.Management.Automation.PSCustomObject

    .EXAMPLE
    Invoke-XdrOperation -Operation 'Get-XdrCurrentUser' -Context $context -ScriptBlock { Invoke-MgGraphRequest -Method GET -Uri '/v1.0/me' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Operation,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [object]$Context,

        [Parameter()]
        [string]$SuccessMessage,

        [Parameter()]
        [string]$FailureMessage,

        [Parameter()]
        [object]$TargetObject
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    function Update-ContextPermissionHealthFromError {
        param(
            [Parameter(Mandatory)]
            [object]$RuntimeContext,

            [Parameter(Mandatory)]
            [string]$ErrorMessage
        )

        if (-not $RuntimeContext -or -not $RuntimeContext.Session) {
            return
        }

        $normalizedError = [regex]::Replace([string]$ErrorMessage, '\s+', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($normalizedError)) {
            return
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

        $permissionPattern = '(?i)Missing user permissions\.?\s*API required permissions:\s*(?<required>.+?)\s*,\s*user permissions:\s*(?<user>.+)$'
        $match = [regex]::Match($normalizedError, $permissionPattern)
        if (-not $match.Success) {
            return
        }

        $requiredPermissions = @($match.Groups['required'].Value -split ',' | ForEach-Object { $_.Trim().TrimEnd('.') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        $availablePermissions = @($match.Groups['user'].Value -split ',' | ForEach-Object { $_.Trim().TrimEnd('.') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

        $RuntimeContext.Session.PermissionHealth.HasSufficientWritePermissions = $false
        $RuntimeContext.Session.PermissionHealth.DetectionSource = 'graph-error'
        $RuntimeContext.Session.PermissionHealth.RequiredPermissions = $requiredPermissions
        $RuntimeContext.Session.PermissionHealth.AvailablePermissions = $availablePermissions
        $RuntimeContext.Session.PermissionHealth.LastUpdatedAt = Get-Date

        if ($RuntimeContext.Capabilities) {
            # Fail closed for mutating actions when Graph reports missing write permissions.
            $RuntimeContext.Capabilities.IncidentActions = @()
            $RuntimeContext.Capabilities.AlertActions = @('GetAlerts')
        }
    }

    try {
        $data = & $ScriptBlock
        $stopwatch.Stop()

        $result = [pscustomobject]@{
            Success   = $true
            Operation = $Operation
            Message   = $(if ($SuccessMessage) { $SuccessMessage } else { "Operation succeeded: $Operation" })
            Data      = $data
            Error     = $null
            Metadata  = [ordered]@{
                TenantId   = $Context.Session.TenantId
                DurationMs = $stopwatch.ElapsedMilliseconds
                Timestamp  = Get-Date
            }
        }

        if ($Context) {
            $Context.Diagnostics.LastOperation = $result
            $Context.Diagnostics.LastError = $null
        }

        return $result
    }
    catch {
        $stopwatch.Stop()

        if ($Context) {
            Update-ContextPermissionHealthFromError -RuntimeContext $Context -ErrorMessage ([string]$_.Exception.Message)
        }

        $errorData = New-XdrErrorRecord -Operation $Operation -ErrorRecord $_ -TargetObject $TargetObject -SafeMessage $FailureMessage

        $result = [pscustomobject]@{
            Success   = $false
            Operation = $Operation
            Message   = $(if ($FailureMessage) { $FailureMessage } else { "Operation failed: $Operation" })
            Data      = $null
            Error     = $errorData
            Metadata  = [ordered]@{
                TenantId   = $Context.Session.TenantId
                DurationMs = $stopwatch.ElapsedMilliseconds
                Timestamp  = Get-Date
            }
        }

        if ($Context) {
            $Context.Diagnostics.LastError = $errorData
            $Context.Diagnostics.LastOperation = $result
        }

        return $result
    }
}