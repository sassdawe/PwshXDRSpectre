function Get-XdrQueryContextGuidance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ContextKey
    )

    switch ([string]$ContextKey) {
        'IncidentId' { 'Select an incident in the incident list first.' }
        'DeviceId' { 'Select a device in the incident entities tab first.' }
        'UserId' { 'Select a user in the incident entities tab first. Manual UserId entry is not implemented yet.' }
        'FileHash' { 'Select a file in the incident entities tab first.' }
        default { "Provide required context: $ContextKey" }
    }
}
