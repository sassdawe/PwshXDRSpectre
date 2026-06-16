function Test-XdrCapability {
    <#
    .SYNOPSIS
    Tests whether a capability is available in runtime context.

    .DESCRIPTION
    Checks the aggregated capability sets in runtime context for the requested
    capability name and can optionally throw when it is unavailable.

    .PARAMETER CapabilityName
    Capability name to look up.

    .PARAMETER Context
    Runtime context containing capability collections.

    .PARAMETER ThrowOnUnknown
    Throws instead of returning false when the capability is unavailable.

    .OUTPUTS
    System.Boolean

    .EXAMPLE
    Test-XdrCapability -CapabilityName 'UpdateIncidentStatus' -Context $context
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CapabilityName,

        [Parameter()]
        [object]$Context,

        [Parameter()]
        [switch]$ThrowOnUnknown
    )

    if (-not $Context -or -not $Context.Capabilities) {
        if ($ThrowOnUnknown.IsPresent) {
            throw "Capability context is missing: $CapabilityName"
        }

        return $false
    }

    $available = @()
    foreach ($setName in @('IncidentActions', 'AlertActions', 'UserActions', 'DeviceActions', 'FileActions')) {
        $setValue = $Context.Capabilities.$setName
        if ($setValue -is [array]) {
            $available += $setValue
        }
        elseif ($setValue) {
            $available += @($setValue)
        }
    }

    $isAllowed = $available -contains $CapabilityName
    if ($isAllowed) {
        return $true
    }

    if ($ThrowOnUnknown.IsPresent) {
        throw "Capability not available: $CapabilityName"
    }

    return $false
}