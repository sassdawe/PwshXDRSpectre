function New-XdrErrorRecord {
    <#
    .SYNOPSIS
    Builds a normalized error record for dashboard operations.

    .DESCRIPTION
    Projects a PowerShell error record into a stable object that captures the
    safe message, category metadata, target details, and timestamp.

    .PARAMETER Operation
    Logical operation name that failed.

    .PARAMETER ErrorRecord
    Source PowerShell error record.

    .PARAMETER TargetObject
    Optional object associated with the failed operation.

    .PARAMETER SafeMessage
    Optional user-safe message to expose to the dashboard.

    .OUTPUTS
    System.Management.Automation.PSCustomObject

    .EXAMPLE
    New-XdrErrorRecord -Operation 'Get-XdrCurrentUser' -ErrorRecord $_ -SafeMessage 'Unable to resolve current user.'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Operation,

        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter()]
        [object]$TargetObject,

        [Parameter()]
        [string]$SafeMessage
    )

    if (-not $SafeMessage) {
        $SafeMessage = "Operation failed: $Operation"
    }

    [pscustomobject]@{
        Operation    = $Operation
        SafeMessage  = $SafeMessage
        Exception    = $ErrorRecord.Exception.Message
        Category     = $ErrorRecord.CategoryInfo.Category.ToString()
        Reason       = $ErrorRecord.CategoryInfo.Reason
        TargetName   = $ErrorRecord.CategoryInfo.TargetName
        TargetObject = $TargetObject
        Timestamp    = Get-Date
    }
}