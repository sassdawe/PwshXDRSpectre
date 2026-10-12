BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrLiveTabOrder' {
    It 'hides live investigation when experimental features are disabled' {
        InModuleScope PwshXDRSpectre {
            $tabOrder = @(Get-XdrLiveTabOrder)

            $tabOrder | Should -Not -Contain 'live_investigation'
            ($tabOrder -join ',') | Should -Be 'welcome,incidents,hunting,query_library,quarantine,action_center,settings,help'
        }
    }

    It 'shows live investigation when experimental features are enabled' {
        InModuleScope PwshXDRSpectre {
            $tabOrder = @(Get-XdrLiveTabOrder -ExperimentalFeaturesEnabled)

            $tabOrder | Should -Contain 'live_investigation'
            ($tabOrder -join ',') | Should -Be 'welcome,incidents,hunting,query_library,quarantine,live_investigation,action_center,settings,help'
        }
    }
}
