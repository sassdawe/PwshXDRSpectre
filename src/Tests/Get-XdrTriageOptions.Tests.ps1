BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrTriageOptions' {
    Context 'comment-based help' {
        It 'has a Synopsis' {
            (Get-Help Get-XdrTriageOptions).Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'has a Description' {
            (Get-Help Get-XdrTriageOptions).Description | Should -Not -BeNullOrEmpty
        }
    }
}