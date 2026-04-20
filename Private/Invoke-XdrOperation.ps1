function Invoke-XdrOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Operation,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [object]$Context,

        [Parameter()]
        [string]$SuccessMessage,

        [Parameter()]
        [string]$FailureMessage,

        [Parameter()]
        [object]$TargetObject
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $data = & $ScriptBlock
        $stopwatch.Stop()

        $result = [pscustomobject]@{
            Success   = $true
            Operation = $Operation
            Message   = $(if ($SuccessMessage) { $SuccessMessage } else { "Operation succeeded: $Operation" })
            Data      = $data
            Error     = $null
            Metadata  = [ordered]@{
                TenantId   = $Context.Session.TenantId
                DurationMs = $stopwatch.ElapsedMilliseconds
                Timestamp  = Get-Date
            }
        }

        if ($Context) {
            $Context.Diagnostics.LastOperation = $result
            $Context.Diagnostics.LastError = $null
        }

        return $result
    }
    catch {
        $stopwatch.Stop()

        $errorData = New-XdrErrorRecord -Operation $Operation -ErrorRecord $_ -TargetObject $TargetObject -SafeMessage $FailureMessage

        $result = [pscustomobject]@{
            Success   = $false
            Operation = $Operation
            Message   = $(if ($FailureMessage) { $FailureMessage } else { "Operation failed: $Operation" })
            Data      = $null
            Error     = $errorData
            Metadata  = [ordered]@{
                TenantId   = $Context.Session.TenantId
                DurationMs = $stopwatch.ElapsedMilliseconds
                Timestamp  = Get-Date
            }
        }

        if ($Context) {
            $Context.Diagnostics.LastError = $errorData
            $Context.Diagnostics.LastOperation = $result
        }

        return $result
    }
}