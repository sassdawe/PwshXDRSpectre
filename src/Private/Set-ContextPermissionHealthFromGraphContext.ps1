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
            $availableScopes = @($graphContext.Scopes | ForEach-Object { ([string]$_).Trim().ToLower() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
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

        $hasIncidentWriteScope = ($availableScopes -contains 'securityincident.readwrite.all')

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