BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Set-LiveStatusMessage' {
    It 'writes prefixed message and notification timestamp' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{
                Ui = [pscustomobject]@{
                    StatusMessage = ''
                    LastNotification = $null
                }
            }

            Set-LiveStatusMessage -Context $context -Message 'done' -Level success

            $context.Ui.StatusMessage | Should -Be 'OK done'
            $context.Ui.LastNotification | Should -BeOfType ([datetime])
            $context.Ui.StatusLevel | Should -Be 'success'
            $context.Ui.StatusExpiresAt | Should -BeOfType ([datetime])
        }
    }

    It 'keeps warning and error messages persistent by default' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{
                Ui = [pscustomobject]@{
                    StatusMessage = ''
                    LastNotification = $null
                    StatusLevel = $null
                    StatusExpiresAt = $null
                }
            }

            Set-LiveStatusMessage -Context $context -Message 'failed' -Level error

            $context.Ui.StatusMessage | Should -Be 'ERR failed'
            $context.Ui.StatusLevel | Should -Be 'error'
            $context.Ui.StatusExpiresAt | Should -BeNullOrEmpty
        }
    }
}