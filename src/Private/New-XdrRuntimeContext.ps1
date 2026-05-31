function New-XdrRuntimeContext {
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
            WorkflowCatalog = @()
            Workflows    = @()
            WorkflowProgress = @{}
            LastRefresh  = $null
        }
        Ui = [pscustomobject][ordered]@{
            Mode              = $Mode
            ThemeColor        = $ThemeColor
            StatusMessage     = $null
            LastNotification  = $null
            RefreshIntervalMs = 200
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