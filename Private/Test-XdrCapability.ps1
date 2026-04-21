function Test-XdrCapability {
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