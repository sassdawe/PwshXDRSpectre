BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrLiveHeaderPanel' {
    It 'falls back to standard panel when figlet render fails' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{
                Ui = [pscustomobject]@{ ThemeColor = 'orange1' }
                Session = [pscustomobject]@{}
            }

            Mock Write-SpectreFigletText { throw 'figlet failed' }
            Mock Format-SpectrePanel { "panel:$Data" }

            $output = Get-XdrLiveHeaderPanel -Context $context -ScriptRoot $PSScriptRoot

            $output | Should -Match 'HELLO XDR SPECTRE'
        }
    }
}