BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Set-XdrIncidentAssignment' {
    Context 'comment-based help' {
        It 'has a Synopsis' {
            (Get-Help Set-XdrIncidentAssignment).Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'has a Description' {
            (Get-Help Set-XdrIncidentAssignment).Description | Should -Not -BeNullOrEmpty
        }
    }
}