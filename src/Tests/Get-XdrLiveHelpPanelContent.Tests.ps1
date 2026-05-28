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
            $selectedIncident = [pscustomobject]@{ IncidentId = 'inc-1' }
            $prefetchCompletedAt = $null

            Mock Get-XdrLiveAlertPrefetchIndicator { 'prefetch 1/2 ======...... active:0 queue:1' }
            Mock Get-SpectreEscapedText { $Text }

            $content = Get-XdrLiveHelpPanelContent -Context $context -SelectedIncident $selectedIncident -AlertsByIncidentId @{ 'inc-1' = @([pscustomobject]@{ AlertId = 'a-1' }) } -AlertLoadJobsByIncidentId @{} -AlertPreloadQueue ([System.Collections.Queue]::new()) -PrefetchCompletedAt ([ref]$prefetchCompletedAt)

            $content | Should -Match 'OK done'
            $content | Should -Match 'prefetch 1/2'
            $content | Should -Match 'Alert cache: warm \(1 alert\)'
            $content | Should -Match 'Last refresh:'
            $content | Should -Match 'F1 Help'
        }
    }

    It 'renders keyboard hint line in default status bar content' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{ Ui = [pscustomobject]@{ StatusMessage = '' } }
            $prefetchCompletedAt = $null

            Mock Get-XdrLiveAlertPrefetchIndicator { '' }
            Mock Get-SpectreEscapedText { $Text }

            $content = Get-XdrLiveHelpPanelContent -Context $context -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId @{} -AlertPreloadQueue ([System.Collections.Queue]::new()) -PrefetchCompletedAt ([ref]$prefetchCompletedAt)

            $content | Should -Match 'Hint:'
            $content | Should -Match 'F1 Help'
            $content | Should -Match 'Tab/Shift\+Tab Switch'
            $content | Should -Match 'q Quit'
        }
    }

    It 'renders keyboard shortcut overlay when requested' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{ Ui = [pscustomobject]@{ StatusMessage = '' } }
            $prefetchCompletedAt = $null

            Mock Get-SpectreEscapedText { $Text }

            $content = Get-XdrLiveHelpPanelContent -Context $context -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId @{} -AlertPreloadQueue ([System.Collections.Queue]::new()) -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -ShowKeyboardHelpOverlay

            $content | Should -Match 'Keyboard Shortcuts'
            $content | Should -Match 'Alt\+Shift\+L'
            $content | Should -Match 'F1'
            $content | Should -Match 'F5'
            $content | Should -Match 'q'
            $content | Should -Match 'Ctrl\+Q'
        }
    }

    It 'renders input debug details when enabled' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{
                Ui = [pscustomobject]@{ StatusMessage = '' }
                Diagnostics = [pscustomobject]@{
                    InputDebugEnabled = $true
                    LastInput = [pscustomobject]@{
                        Key = 'DownArrow'
                        KeyChar = ''
                        Modifiers = 'None'
                        ActivePanel = 'query_catalog'
                        IsQueryMode = $true
                        SelectedQueryIndex = 1
                        SelectedQueryId = 'incident-related-alerts'
                        SelectedEntity = 'user@contoso.com'
                    }
                }
            }
            $prefetchCompletedAt = $null

            Mock Get-XdrLiveAlertPrefetchIndicator { '' }
            Mock Get-SpectreEscapedText { $Text }

            $content = Get-XdrLiveHelpPanelContent -Context $context -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId @{} -AlertPreloadQueue ([System.Collections.Queue]::new()) -PrefetchCompletedAt ([ref]$prefetchCompletedAt) -IsQueryMode

            $content | Should -Match 'Input Debug'
            $content | Should -Match 'Last key: DownArrow'
            $content | Should -Match 'Panel: query catalog'
            $content | Should -Match 'Query index: 1'
            $content | Should -Match 'incident-related-alerts'
            $content | Should -Match 'user@contoso.com'
        }
    }
}