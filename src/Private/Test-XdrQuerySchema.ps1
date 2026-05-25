function Test-XdrQuerySchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Query,

        [Parameter()]
        [object[]]$Catalog = @(),

        [Parameter()]
        [string]$Source = '<memory>'
    )

    $allowedContextKeys = @('IncidentId', 'DeviceId', 'UserId', 'FileHash')
    $requiredFields = @('id', 'name', 'description', 'requiredContext', 'parameters', 'kql', 'displayColumns')
    $queryPropertyNames = @($Query.PSObject.Properties.Name)

    foreach ($field in $requiredFields) {
        if (-not $queryPropertyNames.Contains($field)) {
            throw "Query schema validation failed for '$Source': Missing required field '$field'."
        }
    }

    $queryId = [string]$Query.id
    if ([string]::IsNullOrWhiteSpace($queryId)) {
        throw "Query schema validation failed for '$Source': Field 'id' cannot be empty."
    }

    if ($queryId -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "Query schema validation failed for '$Source': Field 'id' must use slug format."
    }

    if ([string]::IsNullOrWhiteSpace([string]$Query.name)) {
        throw "Query schema validation failed for '$Source': Field 'name' cannot be empty."
    }

    if ([string]::IsNullOrWhiteSpace([string]$Query.description)) {
        throw "Query schema validation failed for '$Source': Field 'description' cannot be empty."
    }

    $duplicateCount = @($Catalog | Where-Object { [string]$_.id -eq $queryId }).Count
    if ($duplicateCount -gt 1) {
        throw "Query schema validation failed for '$Source': Duplicate query id '$queryId'."
    }

    $requiredContext = @($Query.requiredContext)
    foreach ($contextKey in $requiredContext) {
        $contextKeyText = [string]$contextKey
        if (-not $allowedContextKeys.Contains($contextKeyText)) {
            throw "Query schema validation failed for '$Source': Invalid requiredContext value '$contextKeyText'."
        }
    }

    $parameters = @($Query.parameters)
    $parameterNames = @()
    foreach ($parameter in $parameters) {
        $parameterPropertyNames = @($parameter.PSObject.Properties.Name)
        if (-not $parameterPropertyNames.Contains('name')) {
            throw "Query schema validation failed for '$Source': Every parameter must define 'name'."
        }

        $parameterName = [string]$parameter.name
        if ([string]::IsNullOrWhiteSpace($parameterName)) {
            throw "Query schema validation failed for '$Source': Parameter names cannot be empty."
        }

        if ($parameterNames -contains $parameterName) {
            throw "Query schema validation failed for '$Source': Duplicate parameter name '$parameterName'."
        }

        $parameterNames += $parameterName
        $contextBinding = [string]$parameter.contextBinding
        $hasContextBinding = -not [string]::IsNullOrWhiteSpace($contextBinding)
        $hasDefaultValue = $parameterPropertyNames.Contains('defaultValue') -and -not [string]::IsNullOrWhiteSpace([string]$parameter.defaultValue)

        if ($hasContextBinding -and -not $allowedContextKeys.Contains($contextBinding)) {
            throw "Query schema validation failed for '$Source': Parameter '$parameterName' has invalid context binding '$contextBinding'."
        }

        if (-not $hasContextBinding -and -not $hasDefaultValue) {
            throw "Query schema validation failed for '$Source': Parameter '$parameterName' must define a valid context binding or a defaultValue."
        }
    }

    foreach ($requiredContextKey in $requiredContext) {
        $hasBoundParameter = @($parameters | Where-Object { [string]$_.contextBinding -eq [string]$requiredContextKey }).Count -gt 0
        if (-not $hasBoundParameter) {
            throw "Query schema validation failed for '$Source': Required context '$requiredContextKey' is not mapped by any parameter."
        }
    }

    $kql = [string]$Query.kql
    if ([string]::IsNullOrWhiteSpace($kql)) {
        throw "Query schema validation failed for '$Source': Field 'kql' cannot be empty."
    }

    $placeholderNames = @([regex]::Matches($kql, '\{\{\s*([A-Za-z][A-Za-z0-9_]*)\s*\}\}') | ForEach-Object {
        $_.Groups[1].Value
    } | Select-Object -Unique)

    foreach ($placeholderName in $placeholderNames) {
        if ($parameterNames -notcontains $placeholderName) {
            throw "Query schema validation failed for '$Source': KQL placeholder '$placeholderName' does not match any parameter definition."
        }
    }

    $displayColumns = @($Query.displayColumns)
    if ($displayColumns.Count -eq 0) {
        throw "Query schema validation failed for '$Source': Field 'displayColumns' must contain at least one value."
    }

    foreach ($displayColumn in $displayColumns) {
        if ([string]::IsNullOrWhiteSpace([string]$displayColumn)) {
            throw "Query schema validation failed for '$Source': displayColumns cannot contain empty values."
        }
    }

    if ($queryPropertyNames.Contains('tags')) {
        foreach ($tag in @($Query.tags)) {
            if ([string]::IsNullOrWhiteSpace([string]$tag)) {
                throw "Query schema validation failed for '$Source': tags cannot contain empty values."
            }
        }
    }

    return $true
}