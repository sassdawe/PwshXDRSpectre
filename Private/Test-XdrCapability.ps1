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

    $available = @(
        $Context.Capabilities.IncidentActions +
        $Context.Capabilities.AlertActions +
        $Context.Capabilities.UserActions +
        $Context.Capabilities.DeviceActions +
        $Context.Capabilities.FileActions
    )

    $isAllowed = $available -contains $CapabilityName
    if ($isAllowed) {
        return $true
    }

    if ($ThrowOnUnknown.IsPresent) {
        throw "Capability not available: $CapabilityName"
    }

    return $false
}