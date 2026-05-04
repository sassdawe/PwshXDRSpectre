BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-ContextAwareHelpLines' {
    It 'returns resolution-mode guidance when pending resolution exists' {
        InModuleScope PwshXDRSpectre {
            $lines = Get-ContextAwareHelpLines -ActivePanel incidents -PendingIncidentResolution ([pscustomobject]@{ Step = 'determination' })

            $lines | Should -Match 'Incident resolution wizard active'
        }
    }

    It 'returns panel-specific help for alerts panel' {
        InModuleScope PwshXDRSpectre {
            $lines = Get-ContextAwareHelpLines -ActivePanel alerts

            $lines | Should -Match 'Alt\+N/P/M selected alert'
        }
    }
}