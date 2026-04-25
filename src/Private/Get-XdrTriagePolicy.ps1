function Get-XdrTriagePolicy {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = (Join-Path -Path $PSScriptRoot -ChildPath '../config/triage-policy.json')
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Triage policy file not found: $Path"
    }

    $policy = Get-Content -Path $Path -Raw | ConvertFrom-Json
    $requiredSections = @('incidentStatusMap', 'alertStatusMap', 'classifications', 'determinations', 'defaultResolvingComment', 'safetyPolicy')
    foreach ($section in $requiredSections) {
        if (-not $policy.PSObject.Properties.Name.Contains($section)) {
            throw "Triage policy missing required section: $section"
        }
    }

    $validSafetyLevels = @('none', 'confirm', 'disabled')
    $knownActions = @(
        'Assign incident to me',
        'Clear incident assignment',
        'Set incident status to Active',
        'Set incident status to In progress',
        'Set incident status to Resolved',
        'Set incident classification',
        'Set incident determination',
        'Auto-fill resolving comment',
        'Set alert status to New',
        'Set alert status to In progress',
        'Set alert status to Resolved'
    )

    foreach ($mapName in @('incidentStatusMap', 'alertStatusMap', 'classifications', 'determinations')) {
        $map = @($policy.$mapName)
        if (-not $map) {
            throw "Triage policy section must contain at least one entry: $mapName"
        }

        $labels = @($map | ForEach-Object { $_.label })
        $graphValues = @($map | ForEach-Object { $_.graphValue })
        if (($labels | Group-Object | Where-Object Count -gt 1)) {
            throw "Triage policy section contains duplicate labels: $mapName"
        }

        if (($graphValues | Group-Object | Where-Object Count -gt 1)) {
            throw "Triage policy section contains duplicate graph values: $mapName"
        }
    }

    foreach ($entry in @($policy.safetyPolicy)) {
        if (-not $knownActions.Contains($entry.action)) {
            throw "Unknown action in safety policy: $($entry.action)"
        }

        if (-not $validSafetyLevels.Contains($entry.level)) {
            throw "Invalid safety policy level for action '$($entry.action)': $($entry.level)"
        }
    }

    return $policy
}