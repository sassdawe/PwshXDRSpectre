function New-XdrRuntimeContext {
    <#
    .SYNOPSIS
    Creates a fresh runtime context for the dashboard.

    .DESCRIPTION
    Initializes session, selection, data, UI, diagnostics, and capability state
    used by menu and live dashboard workflows.

    .PARAMETER TenantId
    Optional tenant id for the current session.

    .PARAMETER ClientId
    Optional client id for the current session.

    .PARAMETER Mode
    Runtime mode to initialize.

    .PARAMETER ThemeColor
    Accent color used for dashboard rendering.

    .OUTPUTS
    System.Management.Automation.PSCustomObject

    .EXAMPLE
    New-XdrRuntimeContext -TenantId $tenantId -ClientId $clientId -Mode live
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$TenantId,

        [Parameter(Mandatory=$false)]
        [string]$ClientId,

        [Parameter()]
        [ValidateSet('menu', 'live')]
        [string]$Mode = 'menu',

        [Parameter()]
        [string]$ThemeColor = 'Orange1'
    )

    [pscustomobject]@{
        Session = [pscustomobject][ordered]@{
            TenantId    = $TenantId
            ClientId    = $ClientId
            Analyst     = $null
            IsConnected = $false
            StartedAt   = Get-Date
            PermissionHealth = [pscustomobject][ordered]@{
                HasSufficientWritePermissions = $true
                DetectionSource               = 'default'
                RequiredPermissions           = @()
                AvailablePermissions          = @()
                LastUpdatedAt                 = $null
            }
        }
        Selection = [pscustomobject][ordered]@{
            Incident = $null
            Alert    = $null
            Entity   = $null
            Action   = $null
            Panel    = 'incidents'
            Tab      = 'incidents'
        }
        Data = [pscustomobject][ordered]@{
            Incidents    = @()
            Alerts       = @()
            Entities     = @()
            QueryCatalog = @()
            QueryRuns    = @()
            LastRefresh  = $null
        }
        Ui = [pscustomobject][ordered]@{
            Mode                        = $Mode
            ThemeColor                  = $ThemeColor
            StatusMessage               = $null
            LastNotification            = $null
            RefreshIntervalMs           = 200
            ExperimentalFeaturesEnabled = $false
        }
        Capabilities = [pscustomobject][ordered]@{
            IncidentActions = @()
            AlertActions    = @()
            UserActions     = @()
            DeviceActions   = @()
            FileActions     = @()
        }
        Diagnostics = [pscustomobject][ordered]@{
            LastError         = $null
            LastOperation     = $null
            Warnings          = @()
            InputDebugEnabled = $false
            LastInput         = $null
        }
    }
}