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
}