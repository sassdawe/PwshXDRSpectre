BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
    . (Join-Path $PSScriptRoot '..' 'Private' 'ConvertTo-SafeSpectreText.ps1')
}

Describe 'ConvertTo-SafeSpectreText' {
    It 'returns empty for null' {
        ConvertTo-SafeSpectreText -Value $null | Should -Be ''
    }

    It 'escapes non-empty text' {
        Mock Get-SpectreEscapedText { "escaped:$Text" }

        ConvertTo-SafeSpectreText -Value 'abc' | Should -Be 'escaped:abc'
    }
}