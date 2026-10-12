function Get-XdrLiveInvestigationDevice {
    <#
        .SYNOPSIS
        Lists Defender for Endpoint devices that can be used for live investigation.

        .DESCRIPTION
        Queries the Microsoft Defender for Endpoint machine inventory API and returns a
        normalized device view for the live investigation workflow. The function uses the
        existing Microsoft Graph session token through Invoke-MgGraphRequest and fails
        closed unless the runtime context advertises the GetLiveInvestigationDevices
        device capability.

        .PARAMETER Context
        Runtime context created by New-XdrRuntimeContext.

        .PARAMETER MachineId
        Optional Defender for Endpoint machine ID. When supplied, a single machine is
        retrieved.

        .PARAMETER DeviceName
        Optional DNS device name filter.

        .PARAMETER Limit
        Optional maximum number of devices to request from the inventory endpoint.

        .OUTPUTS
        PSCustomObject containing Success, Operation, Message, Data, Error, and Metadata.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter()]
        [string]$MachineId,

        [Parameter()]
        [string]$DeviceName,

        [Parameter()]
        [ValidateRange(1, 500)]
        [int]$Limit = 50
    )

    $operationName = 'Get-XdrLiveInvestigationDevice'
    $capabilityName = 'GetLiveInvestigationDevices'
    if (-not (Test-XdrCapability -CapabilityName $capabilityName -Context $Context)) {
        return [pscustomobject]@{
            Success   = $false
            Operation = $operationName
            Message   = "Capability not available: $capabilityName"
            Data      = $null
            Error     = $null
            Metadata  = [ordered]@{
                TenantId   = $Context.Session.TenantId
                DurationMs = 0
                Timestamp  = Get-Date
            }
        }
    }

    $baseUri = 'https://api.securitycenter.microsoft.com/api/machines'
    if (-not [string]::IsNullOrWhiteSpace($MachineId)) {
        $encodedMachineId = [System.Uri]::EscapeDataString($MachineId)
        $uri = "$baseUri/$encodedMachineId"
    }
    else {
        $queryParts = @()
        if (-not [string]::IsNullOrWhiteSpace($DeviceName)) {
            $escapedDeviceName = $DeviceName.Replace("'", "''")
            $queryParts += "`$filter=computerDnsName eq '$escapedDeviceName'"
        }

        if ($Limit -gt 0) {
            $queryParts += "`$top=$Limit"
        }

        $uri = if ($queryParts.Count -gt 0) { "${baseUri}?$($queryParts -join '&')" } else { $baseUri }
    }

    $operationResult = Invoke-XdrOperation -Operation $operationName -Context $Context -TargetObject $MachineId -ScriptBlock {
        Invoke-MgGraphRequest -Method GET -Uri $uri
    } -SuccessMessage 'Loaded live investigation devices.' -FailureMessage 'Failed to load live investigation devices.'

    if (-not $operationResult.Success) {
        return $operationResult
    }

    $rawDevices = if ($operationResult.Data.PSObject.Properties.Name -contains 'value') {
        @($operationResult.Data.value)
    }
    else {
        @($operationResult.Data)
    }

    $devices = @($rawDevices | Where-Object { $_ } | ForEach-Object {
        [pscustomobject]@{
            MachineId         = [string]$_.id
            DeviceName        = [string]$_.computerDnsName
            AadDeviceId       = [string]$_.aadDeviceId
            HealthStatus      = [string]$_.healthStatus
            RiskScore         = [string]$_.riskScore
            ExposureLevel     = [string]$_.exposureLevel
            OnboardingStatus  = [string]$_.onboardingStatus
            OsPlatform        = [string]$_.osPlatform
            LastSeen          = $_.lastSeen
            LastIpAddress     = [string]$_.lastIpAddress
            DefenderAvStatus  = [string]$_.defenderAvStatus
            RbacGroupName     = [string]$_.rbacGroupName
            Tags              = @($_.machineTags)
        }
    })

    $operationResult | Add-Member -MemberType NoteProperty -Name Data -Value $devices -Force
    $operationResult.Message = "Loaded $($devices.Count) live investigation device(s)."
    return $operationResult
}
