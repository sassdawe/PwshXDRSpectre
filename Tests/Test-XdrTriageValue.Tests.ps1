BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Test-XdrTriageValue' {
    It 'returns true when triage value exists' {
        InModuleScope PwshXDRSpectre {
            Test-XdrTriageValue -MapName 'classifications' -DisplayValue 'True positive / Malware' | Should -BeTrue
        }
    }
}