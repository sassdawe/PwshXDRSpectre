BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrIncidents' {
    Context 'comment-based help' {
        It 'has a Synopsis' {
            (Get-Help Get-XdrIncidents).Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'has a Description' {
            (Get-Help Get-XdrIncidents).Description | Should -Not -BeNullOrEmpty
        }
    }
}