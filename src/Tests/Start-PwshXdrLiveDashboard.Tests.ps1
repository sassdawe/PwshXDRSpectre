BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
    $script:dashboardPath = Join-Path $PSScriptRoot '..' 'Public' 'Start-PwshXdrLiveDashboard.ps1'
}

Describe 'Start-PwshXdrLiveDashboard wiring' {
    It 'does not call Graph mutation cmdlets directly' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content | Should -Not -Match 'Update-MgSecurityIncident'
        $content | Should -Not -Match 'Update-MgSecurityAlertV2'
        $content | Should -Not -Match 'Invoke-MgGraphRequest\s*-Method\s*(POST|PATCH|PUT|DELETE)'
    }

    It 'recomputes disabled reasons for incident and alert actions in render flow' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("Get-XdrActionDisableReasons -ActionName 'Assign incident to me' -ActionType Incident -Context `$context") | Should -BeTrue
        $content.Contains("Get-XdrActionDisableReasons -ActionName 'Clear incident assignment' -ActionType Incident -Context `$context") | Should -BeTrue
        $content.Contains('Get-XdrActionDisableReasons -ActionName "Set incident status to $statusLabel" -ActionType Incident -Context $context -CurrentStatus $selectedIncident.Status -RequestedStatus $requestedStatus') | Should -BeTrue
        $content.Contains('Get-XdrActionDisableReasons -ActionName "Set alert status to $statusLabel" -ActionType Alert -Context $context -CurrentStatus $selectedAlert.Status -RequestedStatus $requestedStatus') | Should -BeTrue
        $content.Contains("`$reasons = @('Unavailable')") | Should -BeTrue
    }

    It 'does not expose PanelFocus in incident or alert detail JSON payloads' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content | Should -Not -Match 'PanelFocus\s*='
    }

    It 'includes incident tags and classification metadata in the incident details payload' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('Classification = $selectedIncident.Classification') | Should -BeTrue
        $content.Contains('SystemTags    = @($selectedIncident.SystemTags)') | Should -BeTrue
        $content.Contains('CustomTags    = @($selectedIncident.CustomTags)') | Should -BeTrue
        $content.Contains('LastUpdated   = $selectedIncident.LastUpdateDateTime') | Should -BeTrue
        $content | Should -Not -Match 'RedirectIncidentId\s*='
    }

    It 'renders incident list entries with severity badge and incident id' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("'Sev ID         Title                                    Status'") | Should -BeTrue
        $content.Contains('$severityColor = switch ($severityKey) {') | Should -BeTrue
        $content.Contains('$statusColor = switch -Regex ($statusKey) {') | Should -BeTrue
        $content.Contains('$idColumn = ("#{0}" -f $incidentIdText)') | Should -BeTrue
        $content.Contains('$titleColumn = $displayNameText') | Should -BeTrue
        $content.Contains("(New-SpectreLayout -Name 'alerts' -Ratio 1 -Data 'empty')") | Should -BeTrue
        $content | Should -Match 'Ⓗ|Ⓜ|Ⓛ|Ⓤ'
    }

    It 'uses nested layout structure with left lists, center details, and right actions columns' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("New-SpectreLayout -Name 'main_content' -Ratio 10 -Columns") | Should -BeTrue
        $content.Contains("New-SpectreLayout -Name 'left_lists' -Ratio 2 -Rows") | Should -BeTrue
        $content.Contains("New-SpectreLayout -Name 'center_details' -Ratio 3 -Rows") | Should -BeTrue
        $content.Contains("(New-SpectreLayout -Name 'incidents' -Ratio 1 -Data 'empty')") | Should -BeTrue
        $content.Contains("(New-SpectreLayout -Name 'alert_details' -Ratio 1 -Data 'empty')") | Should -BeTrue
        $content.Contains("(New-SpectreLayout -Name 'action_status' -Ratio 2 -Data 'empty')") | Should -BeTrue
    }

    It 'renders alert list entries with severity badge incident-style columns and status' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("'Sev Title                                         Status'") | Should -BeTrue
        $content.Contains('$titleText = [string]$_.Title') | Should -BeTrue
        $content.Contains('$statusText = [string]$_.Status') | Should -BeTrue
        $content.Contains('$severityText = [string]$_.Severity') | Should -BeTrue
        $content | Should -Not -Match '\$alertIdText\s*='
    }

    It 'keeps incident resolve mutation inside the final confirm step branch' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("`$currentResolutionStep = [string]`$pendingIncidentResolution.Step") | Should -BeTrue
        $content.Contains('switch ($currentResolutionStep) {') | Should -BeTrue
        $content.Contains("'confirm' {") | Should -BeTrue
        $content.Contains("elseif ((-not `$isAltPressed -and -not `$isCtrlPressed -and `$keyChar -eq 'y') -or `$key.Key -eq 'Enter') {") | Should -BeTrue
        $content.Contains("`$resolveResult = Set-XdrIncidentTriage -Context `$context -IncidentId `$selectedIncident.IncidentId -Status 'Resolved' -Classification `$selectedClassificationLabel -Determination `$selectedDeterminationLabel -Comment `$commentText -SkipConfirmation") | Should -BeTrue
    }

    It 'consumes modal keypresses before normal action-panel Enter handling' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('$keyHandled = $false') | Should -BeTrue
        $content.Contains('if ($null -ne $pendingIncidentResolution) {') | Should -BeTrue
        $content.Contains('$keyHandled = $true') | Should -BeTrue
        $content.Contains('if ($keyHandled) {') | Should -BeTrue
        $content.Contains("elseif (`$key.Key -eq 'Enter' -and `$activePanel -eq 'action_status' -and `$actionEntries.Count -gt 0) {") | Should -BeTrue
    }

    It 'renders incident resolution as a per-step wizard page' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("switch (`$stepName) {") | Should -BeTrue
        $content.Contains("'classification' {") | Should -BeTrue
        $content.Contains("'determination' {") | Should -BeTrue
        $content.Contains("'comment' {") | Should -BeTrue
        $content.Contains("default {") | Should -BeTrue
        $content.Contains("-Title 'Incident Resolution Wizard'") | Should -BeTrue
    }

    It 'uses buffered key capture for text-entry wizard steps' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("`$null -ne `$pendingTextInput -or") | Should -BeTrue
        $content.Contains("(`$null -ne `$pendingIncidentComment -and [string]`$pendingIncidentComment.Step -eq 'comment') -or") | Should -BeTrue
        $content.Contains("(`$null -ne `$pendingIncidentResolution -and [string]`$pendingIncidentResolution.Step -eq 'comment')") | Should -BeTrue
        $content.Contains('@(Get-XdrAllKeysPressed)') | Should -BeTrue
    }

    It 'supports toggling between incident details and related entities panel' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("elseif (`$isAltPressed -and `$keyChar -eq 'e')") | Should -BeTrue
        $content.Contains("elseif (`$isAltPressed -and `$keyChar -eq 'd')") | Should -BeTrue
        $content.Contains("`$activePanel = 'incident_details'") | Should -BeTrue
        $content.Contains("`$panelOrder = @('incidents', 'incident_details', 'alerts', 'action_status')") | Should -BeTrue
        $content.Contains("`$selectedIncidentDetailsTab = 'entities'") | Should -BeTrue
        $content.Contains("`$selectedIncidentDetailsTab = 'details'") | Should -BeTrue
        $content.Contains("[bold black on #C0C0C0]| Incident details |[/][grey70 on #1C1C1C]| Entities |[/] [grey](ALT+E to switch)[/]") | Should -BeTrue
        $content.Contains("[grey70 on #1C1C1C]| Incident details |[/][bold black on #C0C0C0]| Entities |[/] [grey](ALT+D to switch)[/]") | Should -BeTrue
        $content.Contains("Tab to switch to Details") | Should -BeTrue
    }

    It 'extracts entities in background and renders entity-specific preview actions' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('Start-ThreadJob -ScriptBlock {') | Should -BeTrue
        $content.Contains('Get-XdrIncidentEntities -Incident $InnerIncidentData -Alerts $InnerAlertData') | Should -BeTrue
        $content.Contains("'Entity actions (preview)'") | Should -BeTrue
        $content.Contains("`$selectedEntityType = [string]`$selectedEntity.EntityType") | Should -BeTrue
        $content.Contains("'^(?i:user|account)$' { @('Revoke user sessions', 'Disable user account') }") | Should -BeTrue
        $content.Contains("'^(?i:device|machine)$' { @('Isolate device', 'Run antivirus scan', 'Collect investigation package') }") | Should -BeTrue
        $content.Contains("'^(?i:file)$' { @('Quarantine file', 'Block file indicator', 'Remove file indicator block') }") | Should -BeTrue
        $content.Contains("'[grey]No entity selected.[/]'") | Should -BeTrue
        $content.Contains("elseif (`$selectedIncidentDetailsTab -eq 'entities' -and `$key.Key -eq 'DownArrow' -and `$activePanel -eq 'incident_details' -and `$context.Data.Entities.Count -gt 0)") | Should -BeTrue
    }

    It 'supports entity panel up-arrow navigation and selection reset on incident change' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("elseif (`$selectedIncidentDetailsTab -eq 'entities' -and `$key.Key -eq 'UpArrow' -and `$activePanel -eq 'incident_details' -and `$context.Data.Entities.Count -gt 0)") | Should -BeTrue
        $content.Contains("`$selectedEntityIndex = 0") | Should -BeTrue
        $content.Contains("`$selectedEntity = `$null") | Should -BeTrue
        $content.Contains("`$context.Selection.Entity = `$null") | Should -BeTrue
    }

    It 'auto-refreshes incidents every three minutes and passes last refresh to help content' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains('$autoRefreshInterval = [timespan]::FromMinutes(3)') | Should -BeTrue
        $content.Contains("Auto-refreshing incidents and alerts (every 3 minutes)...") | Should -BeTrue
        $content.Contains(". `$resetDashboardDataForRefresh 'Auto-refreshing incidents and alerts (every 3 minutes)...' `$true") | Should -BeTrue
        $content.Contains('-LastRefreshAt $lastDataRefreshAt') | Should -BeTrue
        $content.Contains('[switch]$WithLogs') | Should -BeTrue
        $content.Contains('[string]$LogPath') | Should -BeTrue
        $content.Contains('Dashboard log file: $dashboardLogPath') | Should -BeTrue
    }

    It 'supports keyboard help overlay, quick quit confirmation, and r refresh alias' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("`$pendingQuitConfirmation = `$false") | Should -BeTrue
        $content.Contains("`$showKeyboardHelpOverlay = `$false") | Should -BeTrue
        $content.Contains("elseif (`$key.Key -eq 'F1')") | Should -BeTrue
        $content.Contains("elseif ((-not `$isAltPressed -and -not `$isCtrlPressed -and `$keyChar -eq 'q') -or (`$isCtrlPressed -and -not `$isAltPressed -and `$keyChar -eq 'q'))") | Should -BeTrue
        $content.Contains("elseif (`$key.Key -eq 'F5' -or (-not `$isAltPressed -and -not `$isCtrlPressed -and `$keyChar -eq 'r'))") | Should -BeTrue
        $content.Contains('-ShowKeyboardHelpOverlay:$showKeyboardHelpOverlay') | Should -BeTrue
    }

    Context 'comment-based help' {
        It 'has a Synopsis' {
            (Get-Help Start-PwshXdrLiveDashboard).Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'has a Description' {
            (Get-Help Start-PwshXdrLiveDashboard).Description | Should -Not -BeNullOrEmpty
        }
    }
}
