BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-ContextAwareHelpLines' {
    It 'returns resolution-mode guidance when pending resolution exists' {
        InModuleScope PwshXDRSpectre {
            $lines = Get-ContextAwareHelpLines -ActivePanel incident_list -PendingIncidentResolution ([pscustomobject]@{ Step = 'determination' })

            $lines | Should -Match 'Incident resolution wizard active'
        }
    }

    It 'returns panel-specific help for alerts panel' {
        InModuleScope PwshXDRSpectre {
            $lines = Get-ContextAwareHelpLines -ActivePanel alert_list

            $lines | Should -Match 'Alt\+Shift\+L force reloads selected incident alerts'
            $lines | Should -Match 'Alt\+N/P/M selected alert'
            $lines | Should -Match 'F1 help'
            $lines | Should -Match 'F5/r refresh incidents'
            $lines | Should -Match 'q quit'
            $lines | Should -Match 'Ctrl\+C exit'
        }
    }

    It 'returns incident comment wizard guidance when pending incident comment exists' {
        InModuleScope PwshXDRSpectre {
            $lines = Get-ContextAwareHelpLines -ActivePanel incident_actions -PendingIncidentComment ([pscustomobject]@{ Step = 'comment' })

            $lines | Should -Match 'Incident comment wizard active'
            $lines | Should -Match 'Ctrl\+C exit'
        }
    }

    It 'includes entity and details toggle shortcuts for incident details panel' {
        InModuleScope PwshXDRSpectre {
            $lines = Get-ContextAwareHelpLines -ActivePanel incident_details

            $lines | Should -Match 'Alt\+E show entities'
            $lines | Should -Match 'Alt\+D show incident details'
        }
    }

    It 'returns hunting-mode guidance when query mode is active' {
        InModuleScope PwshXDRSpectre {
            $lines = Get-ContextAwareHelpLines -ActivePanel query_actions -IsQueryMode

            $lines | Should -Match 'Alt\+X run selected query'
            $lines | Should -Match 'Alt\+H return to incident workflow'
            $lines | Should -Match 'Ctrl\+Alt\+A action panel'
            $lines | Should -Match 'Ctrl\+Alt\+K input debug'
        }
    }

    It 'returns query-catalog guidance that Enter executes the selected hunting query' {
        InModuleScope PwshXDRSpectre {
            $lines = Get-ContextAwareHelpLines -ActivePanel query_catalog -IsQueryMode

            $lines | Should -Match 'Enter execute selected query'
            $lines | Should -Match 'Alt\+X execute selected query'
        }
    }
}
