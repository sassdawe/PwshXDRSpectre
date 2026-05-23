BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
    $script:alertLoadJobPath = Join-Path $PSScriptRoot '..' 'Private' 'Start-XdrLiveAlertLoadJob.ps1'
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

    It 'passes an isolated runtime context snapshot to thread jobs' {
        InModuleScope PwshXDRSpectre {
            $jobs = @{}
            $capturedContext = $null
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1' -Mode 'live' -ThemeColor 'Orange1'
            $context.Session.Analyst = 'analyst@example.com'
            $context.Session.IsConnected = $true
            $context.Capabilities.AlertActions = @('GetAlerts', 'UpdateAlertStatus')

            Mock Start-ThreadJob {
                $script:capturedContext = $ArgumentList[1]
                [pscustomobject]@{ Id = 99; State = 'Running' }
            }

            $null = Start-XdrLiveAlertLoadJob -Incident ([pscustomobject]@{ IncidentId = 'inc-1' }) -ModulePath 'module.psm1' -Context $context -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId $jobs

            $script:capturedContext | Should -Not -BeNullOrEmpty
            [object]::ReferenceEquals($script:capturedContext, $context) | Should -BeFalse
            $script:capturedContext.Session.TenantId | Should -Be 'tenant-1'
            $script:capturedContext.Session.ClientId | Should -Be 'client-1'
            $script:capturedContext.Session.Analyst | Should -Be 'analyst@example.com'
            $script:capturedContext.Capabilities.AlertActions | Should -Contain 'GetAlerts'
        }
    }

    It 'logs from thread jobs through module scope' {
        $content = Get-Content -Path $script:alertLoadJobPath -Raw

        $content.Contains('& (Get-Module PwshXDRSpectre) {') | Should -BeTrue
        $content.Contains('Write-XdrLiveDashboardLog -LogPath $InnerJobLogPath -Message "Alert preload job started. IncidentId=$InnerJobIncidentId"') | Should -BeTrue
        $content.Contains('Write-XdrLiveDashboardLog -LogPath $InnerJobLogPath -Message "Alert preload job completed. IncidentId=$InnerJobIncidentId Result=$InnerResultStatus"') | Should -BeTrue
        $content.Contains('} $jobLogPath $jobIncidentId') | Should -BeTrue
        $content.Contains('} $jobLogPath $jobIncidentId $resultStatus') | Should -BeTrue
        $content | Should -Not -Match '\}\s*\$jobLogPath,\s*\$jobIncidentId'
        $content | Should -Not -Match '\}\s*\$jobLogPath,\s*\$jobIncidentId,\s*\$resultStatus'
    }

    It 'carries restore-selection behavior in thread job payloads' {
        $content = Get-Content -Path $script:alertLoadJobPath -Raw

        $content.Contains('[switch]$RestoreSelectionOnCompletion') | Should -BeTrue
        $content.Contains('$RestoreSelectionOnCompletion.IsPresent') | Should -BeTrue
        $content.Contains('RestoreSelectionOnCompletion = [bool]$jobRestoreSelectionOnCompletion') | Should -BeTrue
    }

    It 'loads alert data in thread jobs without mutating shared context directly' {
        $content = Get-Content -Path $script:alertLoadJobPath -Raw

        $content.Contains('Get-XdrAlerts -Context $jobContext -Incident $jobIncident -SkipContextUpdate') | Should -BeTrue
    }
}