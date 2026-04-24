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
        $content.Contains("(New-SpectreLayout -Name 'alerts' -Ratio 3 -Data 'empty')") | Should -BeTrue
        $content | Should -Match 'Ⓗ|Ⓜ|Ⓛ|Ⓤ'
    }

    It 'renders alert list entries with severity badge incident-style columns and status' {
        $content = Get-Content -Path $script:dashboardPath -Raw

        $content.Contains("'Sev Title                                         Status'") | Should -BeTrue
        $content.Contains('$titleText = [string]$_.Title') | Should -BeTrue
        $content.Contains('$statusText = [string]$_.Status') | Should -BeTrue
        $content.Contains('$severityText = [string]$_.Severity') | Should -BeTrue
        $content | Should -Not -Match '\$alertIdText\s*='
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
