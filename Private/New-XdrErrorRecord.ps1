function New-XdrErrorRecord {
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