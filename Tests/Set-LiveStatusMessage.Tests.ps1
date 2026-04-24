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
        }
    }
}