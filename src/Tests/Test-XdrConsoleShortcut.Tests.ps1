BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Test-XdrConsoleShortcut' {
    It 'matches Ctrl+Alt letter shortcuts when the key character is printable' {
        InModuleScope PwshXDRSpectre {
            $key = [System.ConsoleKeyInfo]::new('a', [System.ConsoleKey]::A, $false, $true, $true)

            Test-XdrConsoleShortcut -Key $key -KeyName 'a' -Alt -Control | Should -BeTrue
        }
    }

    It 'matches Ctrl+Alt letter shortcuts when the key character is a control character' {
        InModuleScope PwshXDRSpectre {
            $key = [System.ConsoleKeyInfo]::new([char]1, [System.ConsoleKey]::A, $false, $true, $true)

            Test-XdrConsoleShortcut -Key $key -KeyName 'a' -Alt -Control | Should -BeTrue
        }
    }

    It 'does not match when required modifiers are missing' {
        InModuleScope PwshXDRSpectre {
            $key = [System.ConsoleKeyInfo]::new('a', [System.ConsoleKey]::A, $false, $false, $true)

            Test-XdrConsoleShortcut -Key $key -KeyName 'a' -Alt -Control | Should -BeFalse
        }
    }

    It 'does not match a different physical key' {
        InModuleScope PwshXDRSpectre {
            $key = [System.ConsoleKeyInfo]::new([char]1, [System.ConsoleKey]::A, $false, $true, $true)

            Test-XdrConsoleShortcut -Key $key -KeyName 'k' -Alt -Control | Should -BeFalse
        }
    }
}
