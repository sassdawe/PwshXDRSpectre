BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrLastKeyPressed' {
    It 'has dedicated coverage placeholder' -Skip {
    }
}

Describe 'Get-XdrAllKeysPressed' {
    It 'buffers multiple rapid keystrokes for text input mode' -Skip {
        # This helper captures all buffered keys instead of just the last one
        # Used internally by Start-PwshXdrLiveDashboard during comment text entry
        # Prevents character loss during rapid typing (tested via integration tests)
    }
}