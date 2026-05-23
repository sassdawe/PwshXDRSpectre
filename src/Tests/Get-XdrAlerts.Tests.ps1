BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrAlerts' {
    Context 'comment-based help' {
        It 'has a Synopsis' {
            (Get-Help Get-XdrAlerts).Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'has a Description' {
            (Get-Help Get-XdrAlerts).Description | Should -Not -BeNullOrEmpty
        }
    }

    It 'does not clear visible alerts when skip context update is used and an incident has no alerts' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{
                Data    = [pscustomobject]@{ Alerts = @([pscustomobject]@{ AlertId = 'existing-alert' }) }
                Session = [pscustomobject]@{ TenantId = 'tenant-1' }
            }
            $incident = [pscustomobject]@{ IncidentId = 'inc-1'; AlertRefs = @() }

            $result = Get-XdrAlerts -Context $context -Incident $incident -SkipContextUpdate

            $result.Success | Should -BeTrue
            @($context.Data.Alerts).Count | Should -Be 1
            $context.Data.Alerts[0].AlertId | Should -Be 'existing-alert'
        }
    }

    It 'returns alert data without mutating context when skip context update is used' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{
                Data    = [pscustomobject]@{ Alerts = @([pscustomobject]@{ AlertId = 'existing-alert' }) }
                Session = [pscustomobject]@{ TenantId = 'tenant-1' }
            }
            $incident = [pscustomobject]@{ IncidentId = 'inc-1'; AlertRefs = @([pscustomobject]@{ Id = 'raw-alert-1' }) }

            Mock Invoke-XdrOperation {
                [pscustomobject]@{
                    Success  = $true
                    Data     = @([pscustomobject]@{ Id = 'raw-alert-1' })
                    Metadata = @{}
                }
            }

            Mock ConvertTo-XdrAlertViewModel {
                [pscustomobject]@{
                    AlertId    = $Alert.Id
                    IncidentId = $IncidentId
                }
            }

            $result = Get-XdrAlerts -Context $context -Incident $incident -SkipContextUpdate

            $result.Success | Should -BeTrue
            @($result.Data).Count | Should -Be 1
            $result.Data[0].AlertId | Should -Be 'raw-alert-1'
            @($context.Data.Alerts).Count | Should -Be 1
            $context.Data.Alerts[0].AlertId | Should -Be 'existing-alert'
        }
    }
}