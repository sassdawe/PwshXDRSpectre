#Requires -Version 7 -Modules PwshSpectreConsole, Microsoft.Graph.Authentication, Microsoft.Graph.Security

[CmdletBinding()]
param (
    [system.string[]]$tenantId,
    [system.string]$clientID,
    [int]$limit,
    [switch]$UseDeviceCode
)

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'PwshXDRSpectre.psm1') -Force

$tenant = if ($tenantId -is [array]) { $tenantId[0] } else { $tenantId }
if (-not $tenant) {
    throw 'Parameter tenantId is required.'
}

Start-PwshXdrLiveDashboard -TenantId $tenant -ClientId $clientID -Limit $limit -UseDeviceCode:$UseDeviceCode.IsPresent