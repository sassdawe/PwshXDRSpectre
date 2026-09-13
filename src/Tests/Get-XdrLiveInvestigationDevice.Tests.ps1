BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrLiveInvestigationDevice' {
    It 'queries the Defender machine inventory endpoint and normalizes devices' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.DeviceActions = @('GetLiveInvestigationDevices')
            $script:lastUri = $null

            Mock Invoke-MgGraphRequest {
                $script:lastUri = $Uri
                [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{
                            id                   = 'machine-1'
                            computerDnsName      = 'host-01.contoso.test'
                            healthStatus         = 'Active'
                            riskScore            = 'Medium'
                            osPlatform           = 'Windows10'
                            lastSeen             = '2026-05-31T12:00:00Z'
                            aadDeviceId          = 'device-1'
                            machineTags          = @('prod')
                            rbacGroupName        = 'SOC'
                            exposureLevel        = 'Medium'
                            onboardingStatus     = 'Onboarded'
                            lastIpAddress        = '192.0.2.10'
                            defenderAvStatus     = 'Updated'
                        }
                    )
                }
            }

            $result = Get-XdrLiveInvestigationDevice -Context $context -DeviceName 'host-01.contoso.test' -Limit 5

            $result.Success | Should -BeTrue
            $script:lastUri | Should -Be "https://api.securitycenter.microsoft.com/api/machines?`$filter=computerDnsName eq 'host-01.contoso.test'&`$top=5"
            $result.Data.Count | Should -Be 1
            $result.Data[0].MachineId | Should -Be 'machine-1'
            $result.Data[0].DeviceName | Should -Be 'host-01.contoso.test'
            $result.Data[0].AadDeviceId | Should -Be 'device-1'
        }
    }

    It 'fails closed when the device inventory capability is missing' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'

            Mock Invoke-MgGraphRequest { throw 'should not be called' }

            $result = Get-XdrLiveInvestigationDevice -Context $context

            $result.Success | Should -BeFalse
            $result.Message | Should -Be 'Capability not available: GetLiveInvestigationDevices'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        }
    }
}
