BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrTriagePolicy' {
    It 'loads the default triage policy' {
        InModuleScope PwshXDRSpectre {
            $policy = Get-XdrTriagePolicy

            @($policy.incidentStatusMap).Count | Should -Be 3
            @($policy.alertStatusMap).Count | Should -Be 3
            $policy.defaultResolvingComment | Should -Be 'Incident resolved by current user using PwshXDRSpectre.'
        }
    }

    It 'rejects policy files with unknown safety actions' {
        InModuleScope PwshXDRSpectre {
            $tempPath = Join-Path $TestDrive 'triage-policy.json'
            @'
{
  "incidentStatusMap": [{ "label": "Active", "graphValue": "active" }],
  "alertStatusMap": [{ "label": "New", "graphValue": "new" }],
  "classifications": [{ "label": "Unclassified", "graphValue": "unknown" }],
  "determinations": [{ "label": "Unknown", "graphValue": "unknown" }],
  "defaultResolvingComment": "Resolved using PwshXDRSpectre",
  "safetyPolicy": [{ "action": "Unknown action", "level": "confirm", "prompt": "Bad" }]
}
'@ | Set-Content -Path $tempPath

            { Get-XdrTriagePolicy -Path $tempPath } | Should -Throw 'Unknown action in safety policy*'
        }
    }
}