BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrTriagePolicy and helpers' {
    It 'loads the default triage policy' {
        InModuleScope PwshXDRSpectre {
            $policy = Get-XdrTriagePolicy

            @($policy.incidentStatusMap).Count | Should -Be 3
            @($policy.alertStatusMap).Count | Should -Be 3
            $policy.defaultResolvingComment | Should -Be 'Incident resolved by current user using PwshXDRSpectre.'
        }
    }

    It 'resolves incident status display values to graph values' {
        InModuleScope PwshXDRSpectre {
            Resolve-XdrGraphEnumValue -MapName 'incidentStatusMap' -DisplayValue 'In progress' | Should -Be 'inProgress'
        }
    }

    It 'returns true when triage value exists' {
        InModuleScope PwshXDRSpectre {
            Test-XdrTriageValue -MapName 'classifications' -DisplayValue 'True positive / Malware' | Should -BeTrue
        }
    }

    It 'prefers mail over user principal name for assign target identity' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Session.Analyst = [pscustomobject]@{
                Mail = 'analyst@contoso.com'
                UserPrincipalName = 'analyst-upn@contoso.com'
            }

            Get-XdrAssignTargetIdentity -Context $context | Should -Be 'analyst@contoso.com'
        }
    }

    It 'falls back to user principal name when mail is empty' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Session.Analyst = [pscustomobject]@{
                Mail = ''
                UserPrincipalName = 'analyst-upn@contoso.com'
            }

            Get-XdrAssignTargetIdentity -Context $context | Should -Be 'analyst-upn@contoso.com'
        }
    }

    It 'flags confirm-required actions from the safety policy' {
        InModuleScope PwshXDRSpectre {
            Test-XdrActionSafetyPolicy -ActionName 'Set incident status to Resolved' | Should -BeTrue
            Test-XdrActionSafetyPolicy -ActionName 'Set incident status to In progress' | Should -BeFalse
        }
    }

    It 'returns deterministic disable reasons' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $reasons = Get-XdrActionDisableReasons -ActionName 'Set incident status to Active' -ActionType Incident -Context $context -CurrentStatus 'active' -RequestedStatus 'active'

            $reasons | Should -Contain 'Missing selection context: incident'
            $reasons | Should -Contain 'Missing capability: UpdateIncidentStatus'
            $reasons | Should -Contain 'Invalid transition for current status'
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