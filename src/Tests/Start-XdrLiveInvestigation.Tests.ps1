BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Start-XdrLiveInvestigation' {
    It 'posts a live response command payload for a machine' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.DeviceActions = @('StartLiveInvestigation')
            $script:lastUri = $null
            $script:lastBody = $null
            $script:lastContentType = $null

            Mock Invoke-MgGraphRequest {
                $script:lastUri = $Uri
                $script:lastBody = $Body
                $script:lastContentType = $ContentType
                [pscustomobject]@{
                    id          = 'machine-action-1'
                    type        = 'LiveResponse'
                    status      = 'Pending'
                    requestor   = 'analyst@contoso.test'
                    creationTimeUtc = '2026-05-31T12:00:00Z'
                }
            }

            $result = Start-XdrLiveInvestigation -Context $context -MachineId 'machine-1' -CommandType RunScript -Parameters @{ ScriptName = 'Collect.ps1'; Args = '-Verbose' } -Comment 'Collect live response data' -Confirm:$false

            $result.Success | Should -BeTrue
            $script:lastUri | Should -Be 'https://api.securitycenter.microsoft.com/api/machines/machine-1/runliveresponse'
            $script:lastContentType | Should -Be 'application/json; charset=utf-8'
            $body = $script:lastBody | ConvertFrom-Json
            $body.Comment | Should -Be 'Collect live response data'
            $body.Commands[0].type | Should -Be 'RunScript'
            $body.Commands[0].params.ScriptName | Should -Be 'Collect.ps1'
            $body.Commands[0].params.Args | Should -Be '-Verbose'
            $result.Data.ActionId | Should -Be 'machine-action-1'
            $result.Data.Status | Should -Be 'Pending'
        }
    }

    It 'fails closed when the live investigation capability is missing' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'

            Mock Invoke-MgGraphRequest { throw 'should not be called' }

            $result = Start-XdrLiveInvestigation -Context $context -MachineId 'machine-1' -CommandType RunScript -Parameters @{ ScriptName = 'Collect.ps1' } -Confirm:$false

            $result.Success | Should -BeFalse
            $result.Message | Should -Be 'Capability not available: StartLiveInvestigation'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        }
    }
}
