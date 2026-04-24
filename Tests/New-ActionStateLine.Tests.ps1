BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'New-ActionStateLine' {
    It 'returns label unchanged when no reasons are supplied' {
        InModuleScope PwshXDRSpectre {
            New-ActionStateLine -Label '(Alt+A) Assign' -Reasons @() | Should -Be '(Alt+A) Assign'
        }
    }

    It 'marks the shortcut as unavailable when reasons exist' {
        InModuleScope PwshXDRSpectre {
            New-ActionStateLine -Label '(Alt+A) Assign' -Reasons @('not allowed') | Should -Be '(ⓧ) Assign'
        }
    }
}