BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Set-StatusFromResult' {
    It 'uses warning level when confirmation is required' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{ Ui = [pscustomobject]@{} }
            $result = [pscustomobject]@{
                Success = $false
                Message = 'confirm this'
                Data = [pscustomobject]@{ ConfirmationRequired = $true }
            }

            Mock Set-LiveStatusMessage {}

            Set-StatusFromResult -Context $context -Result $result -PendingMessage 'pending'

            Should -Invoke Set-LiveStatusMessage -Times 1 -ParameterFilter { $Level -eq 'warning' -and $Message -eq 'pending' }
        }
    }
}