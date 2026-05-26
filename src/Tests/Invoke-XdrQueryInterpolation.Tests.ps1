BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Invoke-XdrQueryInterpolation' {
    It 'substitutes placeholders with resolved parameter values' {
        InModuleScope PwshXDRSpectre {
            $query = [pscustomobject]@{
                id         = 'user-signin-anomalies'
                parameters = @(
                    [pscustomobject]@{ name = 'UserId'; contextBinding = 'UserId' },
                    [pscustomobject]@{ name = 'LookbackDays'; contextBinding = $null }
                )
                kql        = "AADSignInEventsBeta | where AccountObjectId == '{{UserId}}' | where Timestamp > ago({{LookbackDays}}d)"
            }

            $result = Invoke-XdrQueryInterpolation -Query $query -Parameters ([ordered]@{
                    UserId       = '11111111-2222-3333-4444-555555555555'
                    LookbackDays = '7'
                })

            $result.Success | Should -BeTrue
            $result.Kql | Should -Be "AADSignInEventsBeta | where AccountObjectId == '11111111-2222-3333-4444-555555555555' | where Timestamp > ago(7d)"
        }
    }

    It 'rejects interpolation when a bound value is injection unsafe' {
        InModuleScope PwshXDRSpectre {
            $query = [pscustomobject]@{
                id         = 'device-process-tree'
                parameters = @(
                    [pscustomobject]@{ name = 'DeviceId'; contextBinding = 'DeviceId' }
                )
                kql        = "DeviceProcessEvents | where DeviceId == '{{DeviceId}}'"
            }

            {
                Invoke-XdrQueryInterpolation -Query $query -Parameters ([ordered]@{
                        DeviceId = "device-1' or 1 == 1 or '"
                    })
            } | Should -Throw '*Unsafe DeviceId value*'
        }
    }
}