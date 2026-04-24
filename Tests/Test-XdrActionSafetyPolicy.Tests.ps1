BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Test-XdrActionSafetyPolicy' {
    It 'flags confirm-required actions from the safety policy' {
        InModuleScope PwshXDRSpectre {
            Test-XdrActionSafetyPolicy -ActionName 'Set incident status to Resolved' | Should -BeTrue
            Test-XdrActionSafetyPolicy -ActionName 'Set incident status to In progress' | Should -BeFalse
        }
    }
}