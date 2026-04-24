function Get-XdrTriageOptions {
    <#
        .SYNOPSIS
        Returns the available triage option values defined by the active triage policy.

        .DESCRIPTION
        Reads the loaded triage policy and surfaces all valid enum values for incident
        statuses, alert statuses, incident classifications, incident determinations, and
        the configured default resolving comment. Use this to populate dropdowns or
        validate user input in scripts and integrations.

        .PARAMETER Policy
        The triage policy object to read. Defaults to the policy returned by
        Get-XdrTriagePolicy.

        .OUTPUTS
        PSCustomObject with IncidentStatuses, AlertStatuses, IncidentClassifications,
        IncidentDeterminations, and DefaultResolvingComment properties.

        .EXAMPLE
        $options = Get-XdrTriageOptions
        $options.IncidentStatuses

        .EXAMPLE
        $options = Get-XdrTriageOptions -Policy (Get-XdrTriagePolicy)

        .NOTES
        Does not require a connected session or Graph permissions.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Policy = (Get-XdrTriagePolicy)
    )

    [pscustomobject]@{
        IncidentStatuses        = @($Policy.incidentStatusMap)
        AlertStatuses           = @($Policy.alertStatusMap)
        IncidentClassifications = @($Policy.classifications)
        IncidentDeterminations  = @($Policy.determinations)
        DefaultResolvingComment = $Policy.defaultResolvingComment
    }
}