function Invoke-XdrHuntingQuery {
    <#
        .SYNOPSIS
        Executes an Advanced Hunting query from the repository catalog.

        .DESCRIPTION
        Resolves context-bound query parameters, safely interpolates them into the
        query's KQL, submits the request to the Microsoft Graph Advanced Hunting
        endpoint, normalizes the response, and records the run in runtime history.

        .PARAMETER Context
        Runtime context created by New-XdrRuntimeContext.

        .PARAMETER Query
        Query definition loaded from Get-XdrQueryCatalog.

        .PARAMETER Timespan
        Optional ISO 8601 timespan passed to the Graph runHuntingQuery API.

        .OUTPUTS
        PSCustomObject containing Success, Operation, Message, Data, Error, and Metadata.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [object]$Query,

        [Parameter()]
        [string]$Timespan
    )

    $queryId = [string]$Query.id
    $queryName = [string]$Query.name

    $parameterResolution = Resolve-XdrQueryParameters -Query $Query -Context $Context
    if ($parameterResolution.IsBlocked) {
        $queryRun = Add-XdrQueryRun -Context $Context -QueryId $queryId -QueryName $queryName -ContextSnapshot $parameterResolution.Parameters -DurationMs 0 -Status 'Failed' -RowCount 0 -ErrorMessage $parameterResolution.Message
        return [pscustomobject]@{
            Success   = $false
            Operation = 'Invoke-XdrHuntingQuery'
            Message   = $parameterResolution.Message
            Data      = [pscustomobject]@{
                QueryId         = $queryId
                QueryName       = $queryName
                IsBlocked       = $true
                MissingContext  = @($parameterResolution.MissingContext)
                ContextSnapshot = [pscustomobject]$parameterResolution.Parameters
                QueryRun        = $queryRun
            }
            Error     = $null
            Metadata  = [ordered]@{
                TenantId   = $Context.Session.TenantId
                DurationMs = 0
                Timestamp  = Get-Date
            }
        }
    }

    try {
        $interpolationResult = Invoke-XdrQueryInterpolation -Query $Query -Parameters $parameterResolution.Parameters
    }
    catch {
        $queryRun = Add-XdrQueryRun -Context $Context -QueryId $queryId -QueryName $queryName -ContextSnapshot $parameterResolution.Parameters -DurationMs 0 -Status 'Failed' -RowCount 0 -ErrorMessage ([string]$_.Exception.Message)
        return [pscustomobject]@{
            Success   = $false
            Operation = 'Invoke-XdrHuntingQuery'
            Message   = [string]$_.Exception.Message
            Data      = [pscustomobject]@{
                QueryId         = $queryId
                QueryName       = $queryName
                IsBlocked       = $false
                MissingContext  = @()
                ContextSnapshot = [pscustomobject]$parameterResolution.Parameters
                QueryRun        = $queryRun
            }
            Error     = $null
            Metadata  = [ordered]@{
                TenantId   = $Context.Session.TenantId
                DurationMs = 0
                Timestamp  = Get-Date
            }
        }
    }

    $body = [ordered]@{
        Query = [string]$interpolationResult.Kql
    }

    if (-not [string]::IsNullOrWhiteSpace($Timespan)) {
        $body.Timespan = $Timespan
    }

    $operationResult = Invoke-XdrOperation -Operation 'Invoke-XdrHuntingQuery' -Context $Context -TargetObject $queryId -ScriptBlock {
        Invoke-MgGraphRequest -Method POST -Uri '/beta/security/runHuntingQuery' -ContentType 'application/json; charset=utf-8' -Body ($body | ConvertTo-Json -Depth 10 -Compress)
    } -SuccessMessage 'Executed Advanced Hunting query successfully.' -FailureMessage 'Failed to execute Advanced Hunting query.'

    if (-not $operationResult.Success) {
        $errorMessage = if ($operationResult.Error) { [string]$operationResult.Error.Message } else { $operationResult.Message }
        $queryRun = Add-XdrQueryRun -Context $Context -QueryId $queryId -QueryName $queryName -ContextSnapshot $parameterResolution.Parameters -DurationMs ([int]$operationResult.Metadata.DurationMs) -Status 'Failed' -RowCount 0 -ErrorMessage $errorMessage
        $operationResult | Add-Member -MemberType NoteProperty -Name Data -Value ([pscustomobject]@{
            QueryId         = $queryId
            QueryName       = $queryName
            QueryText       = [string]$interpolationResult.Kql
            ContextSnapshot = [pscustomobject]$parameterResolution.Parameters
            QueryRun        = $queryRun
        }) -Force
        return $operationResult
    }

    $schema = @($operationResult.Data.schema | ForEach-Object {
        [pscustomobject]@{
            Name = if ($_.PSObject.Properties.Name -contains 'name') { [string]$_.name } else { [string]$_.Name }
            Type = if ($_.PSObject.Properties.Name -contains 'type') { [string]$_.type } else { [string]$_.Type }
        }
    })
    $results = @($operationResult.Data.results)
    $rowCount = $results.Count
    $status = if ($rowCount -gt 0) { 'Success' } else { 'NoResults' }
    $queryRun = Add-XdrQueryRun -Context $Context -QueryId $queryId -QueryName $queryName -ContextSnapshot $parameterResolution.Parameters -DurationMs ([int]$operationResult.Metadata.DurationMs) -Status $status -RowCount $rowCount

    return [pscustomobject]@{
        Success   = $true
        Operation = 'Invoke-XdrHuntingQuery'
        Message   = "Returned $rowCount row(s) for query '$queryName'."
        Data      = [pscustomobject]@{
            QueryId         = $queryId
            QueryName       = $queryName
            QueryText       = [string]$interpolationResult.Kql
            DisplayColumns  = @($Query.displayColumns)
            Schema          = $schema
            Results         = $results
            RowCount        = $rowCount
            ContextSnapshot = [pscustomobject]$parameterResolution.Parameters
            QueryRun        = $queryRun
            Timespan        = $Timespan
        }
        Error     = $null
        Metadata  = $operationResult.Metadata
    }
}