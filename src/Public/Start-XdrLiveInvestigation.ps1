function Start-XdrLiveInvestigation {
    <#
        .SYNOPSIS
        Starts a Defender for Endpoint live investigation command on a device.

        .DESCRIPTION
        Submits a Microsoft Defender for Endpoint Live Response command to an onboarded
        machine. This is the terminal-facing core used by the dashboard's Live
        Investigation tab. The function requires the StartLiveInvestigation device
        capability and uses ShouldProcess confirmation because Live Response can run
        operator-supplied commands on monitored devices.

        .PARAMETER Context
        Runtime context created by New-XdrRuntimeContext.

        .PARAMETER MachineId
        Defender for Endpoint machine ID.

        .PARAMETER CommandType
        Live Response command type to run.

        .PARAMETER Parameters
        Parameters sent to the Live Response command.

        .PARAMETER Comment
        Audit comment sent with the Live Response request.

        .OUTPUTS
        PSCustomObject containing Success, Operation, Message, Data, Error, and Metadata.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$MachineId,

        [Parameter(Mandatory)]
        [ValidateSet('GetFile', 'PutFile', 'RunScript', 'Library')]
        [string]$CommandType,

        [Parameter()]
        [hashtable]$Parameters = @{},

        [Parameter()]
        [string]$Comment = 'Started from PwshXDRSpectre Live Investigation.'
    )

    $operationName = 'Start-XdrLiveInvestigation'
    $capabilityName = 'StartLiveInvestigation'
    if (-not (Test-XdrCapability -CapabilityName $capabilityName -Context $Context)) {
        return [pscustomobject]@{
            Success   = $false
            Operation = $operationName
            Message   = "Capability not available: $capabilityName"
            Data      = $null
            Error     = $null
            Metadata  = [ordered]@{
                TenantId   = $Context.Session.TenantId
                DurationMs = 0
                Timestamp  = Get-Date
            }
        }
    }

    if (-not $PSCmdlet.ShouldProcess($MachineId, "Start Defender live investigation command '$CommandType'")) {
        return [pscustomobject]@{
            Success   = $false
            Operation = $operationName
            Message   = 'Live investigation command was not confirmed.'
            Data      = $null
            Error     = $null
            Metadata  = [ordered]@{
                TenantId   = $Context.Session.TenantId
                DurationMs = 0
                Timestamp  = Get-Date
            }
        }
    }

    $encodedMachineId = [System.Uri]::EscapeDataString($MachineId)
    $uri = "https://api.securitycenter.microsoft.com/api/machines/$encodedMachineId/runliveresponse"
    $commandParameters = [ordered]@{}
    foreach ($key in $Parameters.Keys) {
        $commandParameters[$key] = $Parameters[$key]
    }

    $body = [ordered]@{
        Commands = @(
            [ordered]@{
                type   = $CommandType
                params = $commandParameters
            }
        )
        Comment  = $Comment
    }

    $operationResult = Invoke-XdrOperation -Operation $operationName -Context $Context -TargetObject $MachineId -ScriptBlock {
        Invoke-MgGraphRequest -Method POST -Uri $uri -ContentType 'application/json; charset=utf-8' -Body ($body | ConvertTo-Json -Depth 10 -Compress)
    } -SuccessMessage 'Started live investigation command.' -FailureMessage 'Failed to start live investigation command.'

    if (-not $operationResult.Success) {
        return $operationResult
    }

    $action = $operationResult.Data
    $operationResult | Add-Member -MemberType NoteProperty -Name Data -Value ([pscustomobject]@{
        ActionId        = [string]$action.id
        MachineId       = $MachineId
        CommandType     = $CommandType
        Status          = [string]$action.status
        Type            = [string]$action.type
        Requestor       = [string]$action.requestor
        CreationTimeUtc = $action.creationTimeUtc
        RawAction       = $action
    }) -Force

    return $operationResult
}
