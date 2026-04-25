BeforeAll {
    $script:legacyScript = Get-Content -Path "$PSScriptRoot/../PwshXDRDashboard.ps1" -Raw
}

Describe 'PwshXDRDashboard wrapper' {
    It 'calls Start-PwshXdrLiveDashboard with expected parameters' {
        $script:legacyScript | Should -Match 'Start-PwshXdrLiveDashboard\s+-TenantId\s+\$tenant\s+-ClientId\s+\$clientID\s+-Limit\s+\$limit\s+-UseDeviceCode:\$UseDeviceCode\.IsPresent'
    }
}