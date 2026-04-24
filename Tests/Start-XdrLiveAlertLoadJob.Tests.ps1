BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Start-XdrLiveAlertLoadJob' {
    It 'returns false when incident id is missing' {
        InModuleScope PwshXDRSpectre {
            $result = Start-XdrLiveAlertLoadJob -Incident ([pscustomobject]@{ IncidentId = '' }) -ModulePath 'module.psm1' -Context ([pscustomobject]@{}) -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId @{}

            $result | Should -BeFalse
        }
    }

    It 'starts a thread job for a valid incident' {
        InModuleScope PwshXDRSpectre {
            $jobs = @{}

            Mock Start-ThreadJob { [pscustomobject]@{ Id = 99; State = 'Running' } }

            $result = Start-XdrLiveAlertLoadJob -Incident ([pscustomobject]@{ IncidentId = 'inc-1' }) -ModulePath 'module.psm1' -Context ([pscustomobject]@{}) -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId $jobs

            $result | Should -BeTrue
            $jobs.ContainsKey('inc-1') | Should -BeTrue
        }
    }
}