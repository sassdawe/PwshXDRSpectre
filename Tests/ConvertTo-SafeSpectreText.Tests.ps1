BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'ConvertTo-SafeSpectreText' {
    It 'returns empty for null' {
        InModuleScope PwshXDRSpectre {
            ConvertTo-SafeSpectreText -Value $null | Should -Be ''
        }
    }

    It 'escapes non-empty text' {
        InModuleScope PwshXDRSpectre {
            Mock Get-SpectreEscapedText { "escaped:$Text" }
    
            ConvertTo-SafeSpectreText -Value 'abc' | Should -Be 'escaped:abc'
        }
    }
}