BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Set-XdrAlertStatus' {
    It 'builds proper alert payload for each supported status' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.AlertActions = @('UpdateAlertStatus')

            Mock Update-MgSecurityAlertV2 {
                $script:lastBody = $BodyParameter
                [pscustomobject]@{ Id = $AlertId; Status = $BodyParameter.status }
            }

            $cases = @(
                @{ Display = 'New'; Graph = 'new' },
                @{ Display = 'In progress'; Graph = 'inProgress' },
                @{ Display = 'Resolved'; Graph = 'resolved' }
            )

            foreach ($case in $cases) {
                $script:lastBody = $null
                $result = Set-XdrAlertStatus -Context $context -AlertId 'alert-status' -Status $case.Display -SkipConfirmation

                $result.Success | Should -BeTrue
                $script:lastBody.status | Should -Be $case.Graph
            }
        }
    }

    It 'builds payload for in progress alert updates' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.AlertActions = @('UpdateAlertStatus')

            Mock Update-MgSecurityAlertV2 {
                $script:lastBody = $BodyParameter
                [pscustomobject]@{ Id = $AlertId; Status = $BodyParameter.status }
            }

            $result = Set-XdrAlertStatus -Context $context -AlertId 'alert-1' -Status 'In progress' -SkipConfirmation

            $result.Success | Should -BeTrue
            $script:lastBody.status | Should -Be 'inProgress'
        }
    }

    It 'requires confirmation for reopening an alert to new' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.AlertActions = @('UpdateAlertStatus')

            $result = Set-XdrAlertStatus -Context $context -AlertId 'alert-2' -Status 'New'

            $result.Success | Should -BeFalse
            $result.Data.ConfirmationRequired | Should -BeTrue
            $result.Data.ActionName | Should -Be 'Set alert status to New'
        }
    }

    It 'fails closed when alert capability is missing' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'

            $result = Set-XdrAlertStatus -Context $context -AlertId 'alert-3' -Status 'Resolved' -SkipConfirmation

            $result.Success | Should -BeFalse
            $result.Message | Should -Be 'Capability not available: UpdateAlertStatus'
        }
    }

    It 'fails closed for invalid alert status policy values before Graph mutation' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.AlertActions = @('UpdateAlertStatus')

            $policy = Get-XdrTriagePolicy
            $invalidPolicy = $policy | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $invalidPolicy.alertStatusMap = @($invalidPolicy.alertStatusMap | Where-Object { $_.label -ne 'Resolved' })

            Mock Update-MgSecurityAlertV2 {
                throw 'Graph mutation should not run for invalid policy values.'
            }

            { Set-XdrAlertStatus -Context $context -AlertId 'alert-invalid' -Status 'Resolved' -SkipConfirmation -Policy $invalidPolicy } | Should -Throw "Unknown triage value 'Resolved' for map 'alertStatusMap'"
            Assert-MockCalled Update-MgSecurityAlertV2 -Times 0 -Exactly
        }
    }
}