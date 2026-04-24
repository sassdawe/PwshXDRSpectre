BeforeAll {
    $script:liveScript = Get-Content -Path "$PSScriptRoot/../Invoke-PwshXDRDashboard.ps1" -Raw
}

Describe 'Invoke-PwshXDRDashboard wrapper' {
    It 'calls Start-PwshXdrLiveDashboard with expected parameters' {
        $script:liveScript | Should -Match 'Start-PwshXdrLiveDashboard\s+-TenantId\s+\$tenant\s+-ClientId\s+\$clientID\s+-Limit\s+\$limit\s+-UseDeviceCode:\$UseDeviceCode\.IsPresent'
    }
}