BeforeAll {
    $menuScript = Get-Content -Path "$PSScriptRoot/../PwshXDRDashboard.ps1" -Raw
    $liveScript = Get-Content -Path "$PSScriptRoot/../Invoke-PwshXDRDashboard.ps1" -Raw
}

Describe 'Entry scripts wiring' {
    It 'menu wrapper calls Start-PwshXdrDashboard with expected parameters' {
        $menuScript | Should -Match 'Start-PwshXdrDashboard\s+-TenantId\s+\$tenant\s+-ClientId\s+\$clientID\s+-Limit\s+\$limit\s+-UseDeviceCode:\$UseDeviceCode\.IsPresent'
    }

    It 'live wrapper calls Start-PwshXdrLiveDashboard with expected parameters' {
        $liveScript | Should -Match 'Start-PwshXdrLiveDashboard\s+-TenantId\s+\$tenant\s+-ClientId\s+\$clientID\s+-Limit\s+\$limit\s+-UseDeviceCode:\$UseDeviceCode\.IsPresent'
    }
}
