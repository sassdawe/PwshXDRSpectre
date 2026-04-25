BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'ConvertTo-SafePanelData' {
    It 'returns a single space for empty input' {
        InModuleScope PwshXDRSpectre {
            ConvertTo-SafePanelData -Value '' | Should -Be ' '
        }
    }

    It 'escapes non-empty text' {
        InModuleScope PwshXDRSpectre {
            Mock Get-SpectreEscapedText { "escaped:$Text" }

            ConvertTo-SafePanelData -Value 'abc' | Should -Be 'escaped:abc'
        }
    }
}