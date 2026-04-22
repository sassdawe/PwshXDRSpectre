BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force

    $privateHelpers = @(
        'ConvertTo-SafeSpectreText.ps1',
        'ConvertTo-SafePanelData.ps1',
        'New-ActionStateLine.ps1',
        'Get-PanelHeaderMarkup.ps1',
        'Get-PanelBorderColor.ps1',
        'Set-LiveStatusMessage.ps1',
        'Set-StatusFromResult.ps1',
        'Get-ContextAwareHelpLines.ps1',
        'Get-XdrLiveHeaderPanel.ps1',
        'Restore-XdrLiveCachedAlertsForIncident.ps1',
        'Start-XdrLiveAlertLoadJob.ps1',
        'Invoke-XdrLiveAlertLoadJobProcessing.ps1',
        'Start-XdrLiveQueuedAlertPreloads.ps1',
        'Add-XdrLiveAlertPreloads.ps1',
        'Get-XdrLiveAlertPrefetchIndicator.ps1',
        'Get-XdrLiveHelpPanelContent.ps1',
        'Invoke-XdrLiveActionShortcut.ps1'
    )

    foreach ($helper in $privateHelpers) {
        . (Join-Path $PSScriptRoot '..' 'Private' $helper)
    }
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

Describe 'ConvertTo-SafePanelData' {
    It 'returns a single space for empty input' {
        ConvertTo-SafePanelData -Value '' | Should -Be ' '
    }

    It 'escapes non-empty text' {
        Mock Get-SpectreEscapedText { "escaped:$Text" }
        ConvertTo-SafePanelData -Value 'abc' | Should -Be 'escaped:abc'
    }
}

Describe 'New-ActionStateLine' {
    It 'returns label unchanged when no reasons are supplied' {
        New-ActionStateLine -Label '(Alt+A) Assign' -Reasons @() | Should -Be '(Alt+A) Assign'
    }

    It 'marks the shortcut as unavailable when reasons exist' {
        New-ActionStateLine -Label '(Alt+A) Assign' -Reasons @('not allowed') | Should -Be '(ⓧ) Assign'
    }
}

Describe 'Get-PanelHeaderMarkup' {
    It 'renders active header markup with ACTIVE badge' {
        Get-PanelHeaderMarkup -PanelName 'incidents' -Title 'Incident List' -ActivePanel 'incidents' -Color 'orange1' | Should -Be '[bold orange1]Incident List (ACTIVE)[/]'
    }

    It 'renders inactive header markup in white' {
        Get-PanelHeaderMarkup -PanelName 'alerts' -Title 'Alert List' -ActivePanel 'incidents' -Color 'orange1' | Should -Be '[white]Alert List[/]'
    }
}

Describe 'Get-PanelBorderColor' {
    It 'returns accent for active panel' {
        Get-PanelBorderColor -PanelName 'help' -ActivePanel 'help' -AccentColor 'orange1' | Should -Be 'orange1'
    }

    It 'returns base color for inactive panel' {
        Get-PanelBorderColor -PanelName 'help' -ActivePanel 'incidents' -AccentColor 'orange1' | Should -Be 'deepskyblue1'
    }
}

Describe 'Set-LiveStatusMessage' {
    It 'writes prefixed message and notification timestamp' {
        $context = [pscustomobject]@{
            Ui = [pscustomobject]@{
                StatusMessage = ''
                LastNotification = $null
            }
        }

        Set-LiveStatusMessage -Context $context -Message 'done' -Level success

        $context.Ui.StatusMessage | Should -Be 'OK done'
        $context.Ui.LastNotification | Should -BeOfType ([datetime])
    }
}

Describe 'Set-StatusFromResult' {
    It 'uses warning level when confirmation is required' {
        $context = [pscustomobject]@{ Ui = [pscustomobject]@{} }
        Mock Set-LiveStatusMessage {}

        $result = [pscustomobject]@{
            Success = $false
            Message = 'confirm this'
            Data = [pscustomobject]@{ ConfirmationRequired = $true }
        }

        Set-StatusFromResult -Context $context -Result $result -PendingMessage 'pending'

        Should -Invoke Set-LiveStatusMessage -Times 1 -ParameterFilter { $Level -eq 'warning' -and $Message -eq 'pending' }
    }
}

Describe 'Get-ContextAwareHelpLines' {
    It 'returns resolution-mode guidance when pending resolution exists' {
        $lines = Get-ContextAwareHelpLines -ActivePanel incidents -PendingIncidentResolution ([pscustomobject]@{ Step = 'determination' })
        $lines | Should -Match 'Incident resolution workflow active'
    }

    It 'returns panel-specific help for alerts panel' {
        $lines = Get-ContextAwareHelpLines -ActivePanel alerts
        $lines | Should -Match 'Alt\+N/P/M selected alert'
    }
}

Describe 'Get-XdrLiveHeaderPanel' {
    It 'falls back to standard panel when figlet render fails' {
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

Describe 'Restore-XdrLiveCachedAlertsForIncident' {
    It 'restores cached alerts and selected alert reference' {
        $context = [pscustomobject]@{
            Data = [pscustomobject]@{ Alerts = @() }
            Selection = [pscustomobject]@{ Alert = $null }
        }
        $alertsByIncidentId = @{
            'inc-1' = @(
                [pscustomobject]@{ AlertId = 'a-1' },
                [pscustomobject]@{ AlertId = 'a-2' }
            )
        }
        $selectedMap = @{ 'inc-1' = 'a-2' }
        $selectedAlert = $null
        $selectedAlertIndex = 0

        $result = Restore-XdrLiveCachedAlertsForIncident -IncidentId 'inc-1' -AlertsByIncidentId $alertsByIncidentId -Context $context -SelectedAlertIdByIncidentId $selectedMap -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex)

        $result | Should -BeTrue
        $selectedAlertIndex | Should -Be 1
        $selectedAlert.AlertId | Should -Be 'a-2'
    }
}

Describe 'Start-XdrLiveAlertLoadJob' {
    It 'returns false when incident id is missing' {
        $result = Start-XdrLiveAlertLoadJob -Incident ([pscustomobject]@{ IncidentId = '' }) -ModulePath 'module.psm1' -Context ([pscustomobject]@{}) -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId @{}
        $result | Should -BeFalse
    }

    It 'starts a thread job for a valid incident' {
        $jobs = @{}
        Mock Start-ThreadJob { [pscustomobject]@{ Id = 99; State = 'Running' } }

        $result = Start-XdrLiveAlertLoadJob -Incident ([pscustomobject]@{ IncidentId = 'inc-1' }) -ModulePath 'module.psm1' -Context ([pscustomobject]@{}) -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId $jobs

        $result | Should -BeTrue
        $jobs.ContainsKey('inc-1') | Should -BeTrue
    }
}

Describe 'Invoke-XdrLiveAlertLoadJobProcessing' {
    It 'stores loaded alerts and clears completed job entry' {
        $job = Start-Job -ScriptBlock {
            [pscustomobject]@{
                IncidentId = 'inc-1'
                Result = [pscustomobject]@{
                    Success = $true
                    Data = @([pscustomobject]@{ AlertId = 'a-1' })
                }
            }
        }
        Wait-Job -Job $job | Out-Null
        $jobs = @{ 'inc-1' = $job }
        $cache = @{}
        $selectedIncident = [pscustomobject]@{ IncidentId = 'inc-1' }
        $context = [pscustomobject]@{ Data = [pscustomobject]@{}; Selection = [pscustomobject]@{} }
        $selectedMap = @{}
        $selectedAlert = $null
        $selectedAlertIndex = 0

        Mock Restore-XdrLiveCachedAlertsForIncident { $true }

        Invoke-XdrLiveAlertLoadJobProcessing -AlertLoadJobsByIncidentId $jobs -AlertsByIncidentId $cache -SelectedIncident $selectedIncident -Context $context -SelectedAlertIdByIncidentId $selectedMap -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex)

        $jobs.ContainsKey('inc-1') | Should -BeFalse
        $cache.ContainsKey('inc-1') | Should -BeTrue
        Should -Invoke Restore-XdrLiveCachedAlertsForIncident -Times 1
    }
}

Describe 'Start-XdrLiveQueuedAlertPreloads' {
    It 'dequeues and starts jobs up to max concurrency' {
        $jobs = @{}
        $queue = [System.Collections.Queue]::new()
        $queue.Enqueue([pscustomobject]@{ IncidentId = 'inc-1' })
        $queue.Enqueue([pscustomobject]@{ IncidentId = 'inc-2' })

        Mock Start-XdrLiveAlertLoadJob {
            $AlertLoadJobsByIncidentId[[string]$Incident.IncidentId] = [pscustomobject]@{ State = 'Running' }
            $true
        }

        Start-XdrLiveQueuedAlertPreloads -AlertLoadJobsByIncidentId $jobs -MaxAlertLoadJobs 1 -AlertPreloadQueue $queue -ModulePath 'module.psm1' -Context ([pscustomobject]@{}) -AlertsByIncidentId @{}

        $jobs.Count | Should -Be 1
        $queue.Count | Should -Be 1
    }
}

Describe 'Add-XdrLiveAlertPreloads' {
    It 'queues only incidents that are neither cached nor loading' {
        $incidents = @(
            [pscustomobject]@{ IncidentId = 'inc-1' },
            [pscustomobject]@{ IncidentId = 'inc-2' },
            [pscustomobject]@{ IncidentId = 'inc-3' }
        )
        $queue = [System.Collections.Queue]::new()
        $cache = @{ 'inc-1' = @() }
        $jobs = @{ 'inc-2' = [pscustomobject]@{ State = 'Running' } }

        Add-XdrLiveAlertPreloads -Incidents $incidents -AlertPreloadQueue $queue -AlertsByIncidentId $cache -AlertLoadJobsByIncidentId $jobs

        $queue.Count | Should -Be 1
        $queue.Peek().IncidentId | Should -Be 'inc-3'
    }
}

Describe 'Get-XdrLiveAlertPrefetchIndicator' {
    It 'returns progress line while prefetch is in progress' {
        $context = [pscustomobject]@{
            Data = [pscustomobject]@{
                Incidents = @(
                    [pscustomobject]@{ IncidentId = 'inc-1' },
                    [pscustomobject]@{ IncidentId = 'inc-2' }
                )
            }
        }
        $cache = @{ 'inc-1' = @() }
        $jobs = @{}
        $queue = [System.Collections.Queue]::new()
        $prefetchCompletedAt = $null

        $line = Get-XdrLiveAlertPrefetchIndicator -Context $context -AlertsByIncidentId $cache -AlertLoadJobsByIncidentId $jobs -AlertPreloadQueue $queue -PrefetchCompletedAt ([ref]$prefetchCompletedAt)

        $line | Should -Match '^prefetch 1/2 '
    }
}

Describe 'Get-XdrLiveHelpPanelContent' {
    It 'renders text input mode content' {
        Mock Get-SpectreEscapedText { $Text }
        $context = [pscustomobject]@{ Ui = [pscustomobject]@{ StatusMessage = '' } }
        $pendingTextInput = [pscustomobject]@{
            Title = 'COMMENT'
            Prompt = 'Say something'
            Value = ''
        }
        $prefetchCompletedAt = $null

        $content = Get-XdrLiveHelpPanelContent -Context $context -PendingTextInput $pendingTextInput -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId @{} -AlertPreloadQueue ([System.Collections.Queue]::new()) -PrefetchCompletedAt ([ref]$prefetchCompletedAt)

        $content | Should -Match 'COMMENT'
        $content | Should -Match 'Enter submit'
    }

    It 'renders status and prefetch line when available' {
        Mock Get-XdrLiveAlertPrefetchIndicator { 'prefetch 1/2 ======...... active:0 queue:1' }
        Mock Get-SpectreEscapedText { $Text }
        $context = [pscustomobject]@{ Ui = [pscustomobject]@{ StatusMessage = 'OK done' } }
        $prefetchCompletedAt = $null

        $content = Get-XdrLiveHelpPanelContent -Context $context -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId @{} -AlertPreloadQueue ([System.Collections.Queue]::new()) -PrefetchCompletedAt ([ref]$prefetchCompletedAt)

        $content | Should -Match 'OK done'
        $content | Should -Match 'prefetch 1/2'
    }
}

Describe 'Invoke-XdrLiveActionShortcut' {
    It 'shows warning when load-alert shortcut is used with no selected incident' {
        $context = [pscustomobject]@{
            Ui = [pscustomobject]@{
                StatusMessage = ''
                LastNotification = $null
            }
            Selection = [pscustomobject]@{ Panel = 'incidents' }
        }

        $activePanel = 'incidents'
        $activePanelIndex = 0
        $activePanelBeforeResolution = $null
        $pendingConfirmation = $null
        $pendingTextInput = $null
        $pendingIncidentResolution = $null
        $selectedAlertIndex = 0

        Invoke-XdrLiveActionShortcut -Shortcut 'l' -Context $context -SelectedIncident $null -SelectedAlert $null -TriageOptions ([pscustomobject]@{ IncidentDeterminations = @('TruePositive') }) -PanelOrder @('incidents','incident_details','alerts','alert_details','action_status') -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -ActivePanelBeforeResolution ([ref]$activePanelBeforeResolution) -PendingConfirmation ([ref]$pendingConfirmation) -PendingTextInput ([ref]$pendingTextInput) -PendingIncidentResolution ([ref]$pendingIncidentResolution) -ModulePath 'module.psm1' -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId @{} -SelectedAlertIdByIncidentId @{} -SelectedAlertIndex ([ref]$selectedAlertIndex)

        $context.Ui.StatusMessage | Should -Be 'WARN No incident is selected for loading alerts.'
    }
}
