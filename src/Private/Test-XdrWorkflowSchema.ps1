function Test-XdrWorkflowSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Workflow,

        [Parameter()]
        [object[]]$Catalog = @(),

        [Parameter()]
        [string]$Source = '<memory>'
    )

    $allowedContextKeys = @('IncidentId', 'AlertId', 'DeviceId', 'UserId', 'FileHash', 'Entity')
    $allowedConditionFields = @('severity', 'status', 'classification', 'tags', 'serviceSource', 'category', 'entityType')
    $allowedOperators = @('equals', 'notEquals', 'contains', 'in')
    $requiredFields = @('id', 'name', 'description', 'conditions', 'steps')
    $workflowPropertyNames = @($Workflow.PSObject.Properties.Name)

    foreach ($field in $requiredFields) {
        if (-not $workflowPropertyNames.Contains($field)) {
            throw "Workflow schema validation failed for '$Source': Missing required field '$field'."
        }
    }

    $workflowId = [string]$Workflow.id
    if ([string]::IsNullOrWhiteSpace($workflowId)) {
        throw "Workflow schema validation failed for '$Source': Field 'id' cannot be empty."
    }

    if ($workflowId -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "Workflow schema validation failed for '$Source': Field 'id' must use slug format."
    }

    if ([string]::IsNullOrWhiteSpace([string]$Workflow.name)) {
        throw "Workflow schema validation failed for '$Source': Field 'name' cannot be empty."
    }

    if ([string]::IsNullOrWhiteSpace([string]$Workflow.description)) {
        throw "Workflow schema validation failed for '$Source': Field 'description' cannot be empty."
    }

    $duplicateCount = @($Catalog | Where-Object { [string]$_.id -eq $workflowId }).Count
    if ($duplicateCount -gt 1) {
        throw "Workflow schema validation failed for '$Source': Duplicate workflow id '$workflowId'."
    }

    if ($workflowPropertyNames.Contains('requiredContext')) {
        foreach ($contextKey in @($Workflow.requiredContext)) {
            $contextKeyText = [string]$contextKey
            if (-not $allowedContextKeys.Contains($contextKeyText)) {
                throw "Workflow schema validation failed for '$Source': Invalid requiredContext value '$contextKeyText'."
            }
        }
    }

    $matchMode = if ($workflowPropertyNames.Contains('match')) { [string]$Workflow.match } else { 'all' }
    if ($matchMode -notin @('all', 'any')) {
        throw "Workflow schema validation failed for '$Source': Field 'match' must be 'all' or 'any'."
    }

    $conditions = @($Workflow.conditions)
    if ($conditions.Count -eq 0) {
        throw "Workflow schema validation failed for '$Source': Field 'conditions' must contain at least one condition."
    }

    foreach ($condition in $conditions) {
        $conditionPropertyNames = @($condition.PSObject.Properties.Name)
        foreach ($field in @('field', 'operator')) {
            if (-not $conditionPropertyNames.Contains($field)) {
                throw "Workflow schema validation failed for '$Source': Every condition must define '$field'."
            }
        }

        $conditionField = [string]$condition.field
        if (-not $allowedConditionFields.Contains($conditionField)) {
            throw "Workflow schema validation failed for '$Source': Invalid condition field '$conditionField'."
        }

        $conditionOperator = [string]$condition.operator
        if (-not $allowedOperators.Contains($conditionOperator)) {
            throw "Workflow schema validation failed for '$Source': Invalid condition operator '$conditionOperator'."
        }

        if (-not $conditionPropertyNames.Contains('value') -and -not $conditionPropertyNames.Contains('values')) {
            throw "Workflow schema validation failed for '$Source': Condition '$conditionField' must define value or values."
        }
    }

    $steps = @($Workflow.steps)
    if ($steps.Count -eq 0) {
        throw "Workflow schema validation failed for '$Source': Field 'steps' must contain at least one step."
    }

    foreach ($step in $steps) {
        $stepPropertyNames = @($step.PSObject.Properties.Name)
        foreach ($field in @('title', 'guidance')) {
            if (-not $stepPropertyNames.Contains($field) -or [string]::IsNullOrWhiteSpace([string]$step.$field)) {
                throw "Workflow schema validation failed for '$Source': Every step must define non-empty '$field'."
            }
        }

        if ($stepPropertyNames.Contains('links')) {
            foreach ($link in @($step.links)) {
                if ([string]::IsNullOrWhiteSpace([string]$link)) {
                    throw "Workflow schema validation failed for '$Source': links cannot contain empty values."
                }
            }
        }

        if ($stepPropertyNames.Contains('evidence')) {
            foreach ($evidence in @($step.evidence)) {
                if ([string]::IsNullOrWhiteSpace([string]$evidence)) {
                    throw "Workflow schema validation failed for '$Source': evidence cannot contain empty values."
                }
            }
        }
    }

    if ($workflowPropertyNames.Contains('tags')) {
        foreach ($tag in @($Workflow.tags)) {
            if ([string]::IsNullOrWhiteSpace([string]$tag)) {
                throw "Workflow schema validation failed for '$Source': tags cannot contain empty values."
            }
        }
    }

    return $true
}
