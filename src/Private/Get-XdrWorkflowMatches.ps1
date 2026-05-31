function Get-XdrWorkflowContextValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Field,

        [Parameter()]
        [object]$Context
    )

    $incident = $Context.Selection.Incident
    $alert = $Context.Selection.Alert
    $entity = $Context.Selection.Entity

    switch ($Field) {
        'severity' { return @($incident.Severity, $alert.Severity | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
        'status' { return @($incident.Status, $alert.Status | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
        'classification' { return @($incident.Classification | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
        'tags' { return @($incident.SystemTags + $incident.CustomTags + $alert.Tags | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
        'serviceSource' { return @($alert.ServiceSource, $incident.ServiceSource | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
        'category' { return @($alert.Category, $incident.Category | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
        'entityType' { return @($entity.EntityType, $entity.Type | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
        default { return @() }
    }
}

function Test-XdrWorkflowCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Condition,

        [Parameter(Mandatory)]
        [object]$Context
    )

    $actualValues = @(Get-XdrWorkflowContextValues -Field ([string]$Condition.field) -Context $Context | ForEach-Object { [string]$_ })
    $expectedValues = if (@($Condition.PSObject.Properties.Name).Contains('values')) { @($Condition.values) } else { @($Condition.value) }
    $expectedValues = @($expectedValues | ForEach-Object { [string]$_ })
    $actualLower = @($actualValues | ForEach-Object { $_.ToLowerInvariant() })
    $expectedLower = @($expectedValues | ForEach-Object { $_.ToLowerInvariant() })

    $matched = switch ([string]$Condition.operator) {
        'equals' { @($actualLower | Where-Object { $expectedLower -contains $_ }).Count -gt 0 }
        'notEquals' { @($actualLower | Where-Object { $expectedLower -contains $_ }).Count -eq 0 }
        'contains' {
            $foundContains = $false
            foreach ($actual in $actualLower) {
                foreach ($expected in $expectedLower) {
                    if ($actual.Contains($expected)) { $foundContains = $true }
                }
            }
            $foundContains
        }
        'in' { @($actualLower | Where-Object { $expectedLower -contains $_ }).Count -gt 0 }
        default { $false }
    }

    [pscustomobject]@{
        Field    = [string]$Condition.field
        Matched  = [bool]$matched
        Expected = @($expectedValues)
        Actual   = @($actualValues)
        Reason   = "$([string]$Condition.field) $([string]$Condition.operator) $($expectedValues -join ', ')"
    }
}

function Get-XdrWorkflowMatches {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Catalog = @(),

        [Parameter(Mandatory)]
        [object]$Context
    )

    $matches = @()
    foreach ($workflow in @($Catalog)) {
        try {
            $conditionResults = @($workflow.conditions | ForEach-Object {
                Test-XdrWorkflowCondition -Condition $_ -Context $Context
            })
            $matchMode = if (@($workflow.PSObject.Properties.Name).Contains('match')) { [string]$workflow.match } else { 'all' }
            $isMatch = if ($matchMode -eq 'any') {
                @($conditionResults | Where-Object { $_.Matched }).Count -gt 0
            }
            else {
                @($conditionResults | Where-Object { -not $_.Matched }).Count -eq 0
            }

            if ($isMatch) {
                $triggerReasons = @($conditionResults | Where-Object { $_.Matched } | ForEach-Object { $_.Reason })
                $matches += [pscustomobject]@{
                    Workflow      = $workflow
                    TriggerReason = if ($triggerReasons.Count -gt 0) { $triggerReasons -join '; ' } else { 'Matched workflow conditions' }
                    Conditions    = @($conditionResults)
                }
            }
        }
        catch {
            $Context.Diagnostics.Warnings = @($Context.Diagnostics.Warnings + "Workflow '$([string]$workflow.id)' skipped: $($_.Exception.Message)")
        }
    }

    return @($matches)
}
