BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Invoke-XdrHuntingQuery' {
    It 'builds the Graph request payload and returns a normalized result set' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Selection.Entity = [pscustomobject]@{ DeviceId = 'device-123' }
            $script:lastUri = $null
            $script:lastBody = $null
            $script:lastContentType = $null

            Mock Invoke-MgGraphRequest {
                $script:lastUri = $Uri
                $script:lastBody = $Body
                $script:lastContentType = $ContentType
                [pscustomobject]@{
                    schema = @(
                        [pscustomobject]@{ name = 'Timestamp'; type = 'DateTime' },
                        [pscustomobject]@{ Name = 'DeviceName'; Type = 'String' }
                    )
                    results = @(
                        [pscustomobject]@{ Timestamp = '2026-05-23T12:00:00Z'; DeviceName = 'host-01' }
                    )
                }
            }

            $query = [pscustomobject]@{
                id             = 'device-process-tree'
                name           = 'Device Process Tree'
                requiredContext = @('DeviceId')
                parameters     = @(
                    [pscustomobject]@{ name = 'DeviceId'; contextBinding = 'DeviceId'; description = 'Device id' },
                    [pscustomobject]@{ name = 'LookbackHours'; contextBinding = $null; defaultValue = '24'; description = 'Lookback' }
                )
                kql            = "DeviceProcessEvents | where DeviceId == '{{DeviceId}}' | where Timestamp > ago({{LookbackHours}}h)"
                displayColumns = @('Timestamp', 'DeviceName')
            }

            $result = Invoke-XdrHuntingQuery -Context $context -Query $query -Timespan 'P7D'

            $result.Success | Should -BeTrue
            $script:lastUri | Should -Be '/beta/security/runHuntingQuery'
            $script:lastContentType | Should -Be 'application/json; charset=utf-8'
            (($script:lastBody | ConvertFrom-Json).Query) | Should -Be "DeviceProcessEvents | where DeviceId == 'device-123' | where Timestamp > ago(24h)"
            (($script:lastBody | ConvertFrom-Json).Timespan) | Should -Be 'P7D'
            $result.Data.RowCount | Should -Be 1
            $result.Data.Schema[0].Name | Should -Be 'Timestamp'
            $result.Data.Schema[1].Name | Should -Be 'DeviceName'
            $result.Data.Results[0].DeviceName | Should -Be 'host-01'
            $context.Data.QueryRuns.Count | Should -Be 1
            $context.Data.QueryRuns[0].Status | Should -Be 'Success'
        }
    }

    It 'records a failed query run when required context is missing' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $query = [pscustomobject]@{
                id              = 'incident-related-alerts'
                name            = 'Incident Related Alerts'
                requiredContext = @('IncidentId')
                parameters      = @(
                    [pscustomobject]@{ name = 'IncidentId'; contextBinding = 'IncidentId'; description = 'Incident id' }
                )
                kql             = "AlertInfo | where IncidentId == '{{IncidentId}}'"
                displayColumns  = @('IncidentId')
            }

            $result = Invoke-XdrHuntingQuery -Context $context -Query $query

            $result.Success | Should -BeFalse
            $result.Data.IsBlocked | Should -BeTrue
            $result.Data.MissingContext | Should -Be @('IncidentId')
            $context.Data.QueryRuns.Count | Should -Be 1
            $context.Data.QueryRuns[0].Status | Should -Be 'Failed'
        }
    }
}