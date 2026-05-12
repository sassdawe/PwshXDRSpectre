BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrLiveHelpPanelContent' {
    It 'renders text input mode content' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{ Ui = [pscustomobject]@{ StatusMessage = '' } }
            $lastRefreshAt = [datetime]'2026-05-12T10:11:12'
            $pendingTextInput = [pscustomobject]@{
                Title = 'COMMENT'
                Prompt = 'Say something'
                Value = ''
            }
            $prefetchCompletedAt = $null

            Mock Get-SpectreEscapedText { $Text }

            $content = Get-XdrLiveHelpPanelContent -Context $context -PendingTextInput $pendingTextInput -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId @{} -AlertPreloadQueue ([System.Collections.Queue]::new()) -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -LastRefreshAt $lastRefreshAt

            $content | Should -Match 'COMMENT'
            $content | Should -Match 'Enter submit'
            $content | Should -Match 'Last refresh:'
        }
    }

    It 'renders status and prefetch line when available' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{ Ui = [pscustomobject]@{ StatusMessage = 'OK done' } }
            $prefetchCompletedAt = $null

            Mock Get-XdrLiveAlertPrefetchIndicator { 'prefetch 1/2 ======...... active:0 queue:1' }
            Mock Get-SpectreEscapedText { $Text }

            $content = Get-XdrLiveHelpPanelContent -Context $context -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId @{} -AlertPreloadQueue ([System.Collections.Queue]::new()) -PrefetchCompletedAt ([ref]$prefetchCompletedAt)

            $content | Should -Match 'OK done'
            $content | Should -Match 'prefetch 1/2'
            $content | Should -Match 'Last refresh:'
        }
    }
}