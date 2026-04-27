BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Set-XdrIncidentTriage' {
    It 'builds proper incident payload for each supported status' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('UpdateIncidentStatus')

            Mock Update-MgSecurityIncident {
                $script:lastBody = $BodyParameter
                [pscustomobject]@{ Id = $IncidentId; Status = $BodyParameter.status }
            }

            $cases = @(
                @{ Display = 'Active'; Graph = 'active' },
                @{ Display = 'In progress'; Graph = 'inProgress' },
                @{ Display = 'Resolved'; Graph = 'resolved' }
            )

            foreach ($case in $cases) {
                $script:lastBody = $null
                $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-status' -Status $case.Display -SkipConfirmation

                $result.Success | Should -BeTrue
                $script:lastBody.status | Should -Be $case.Graph
            }
        }
    }

    It 'builds status payload for in progress updates' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('UpdateIncidentStatus')

            Mock Update-MgSecurityIncident {
                $script:lastBody = $BodyParameter
                [pscustomobject]@{ Id = $IncidentId; Status = $BodyParameter.status }
            }

            $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-1' -Status 'In progress' -SkipConfirmation

            $result.Success | Should -BeTrue
            $script:lastBody.status | Should -Be 'inProgress'
        }
    }

    It 'auto-fills resolving comment when resolving without a comment' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('UpdateIncidentStatus')

            Mock Update-MgSecurityIncident {
                $script:lastBody = $BodyParameter
                [pscustomobject]@{ Id = $IncidentId; Status = $BodyParameter.status }
            }

            $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-2' -Status 'Resolved' -SkipConfirmation

            $result.Success | Should -BeTrue
            $script:lastBody.status | Should -Be 'resolved'
            $script:lastBody.resolvingComment | Should -Be 'Incident resolved by current user using PwshXDRSpectre.'
        }
    }

    It 'uses analyst identity in auto-filled resolving comment when available' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('UpdateIncidentStatus')
            $context.Session.Analyst = [pscustomobject]@{
                DisplayName = 'Alex Analyst'
                UserPrincipalName = 'alex@contoso.com'
                Mail = 'alex@contoso.com'
            }

            Mock Update-MgSecurityIncident {
                $script:lastBody = $BodyParameter
                [pscustomobject]@{ Id = $IncidentId; Status = $BodyParameter.status }
            }

            $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-2b' -Status 'Resolved' -SkipConfirmation

            $result.Success | Should -BeTrue
            $script:lastBody.status | Should -Be 'resolved'
            $script:lastBody.resolvingComment | Should -Be 'Incident resolved by Alex Analyst using PwshXDRSpectre.'
        }
    }

    It 'posts a normal incident comment using the incident comments endpoint' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $script:updateCalled = $false
            $script:lastCommentUri = $null
            $script:lastCommentBody = $null

            Mock Update-MgSecurityIncident {
                $script:updateCalled = $true
                [pscustomobject]@{ Id = $IncidentId }
            }

            Mock Invoke-MgGraphRequest {
                $script:lastCommentUri = $Uri
                $script:lastCommentBody = $Body
                [pscustomobject]@{ value = @() }
            }

            $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-2c' -Comment 'Normal note' -SkipConfirmation

            $result.Success | Should -BeTrue
            $script:updateCalled | Should -BeFalse
            $script:lastCommentUri | Should -Be '/v1.0/security/incidents/inc-2c/comments'
            (($script:lastCommentBody | ConvertFrom-Json).comment) | Should -Be 'Normal note'
        }
    }

    It 'requires confirmation for resolved incident status when not skipped' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('UpdateIncidentStatus')

            $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-3' -Status 'Resolved'

            $result.Success | Should -BeFalse
            $result.Data.ConfirmationRequired | Should -BeTrue
            $result.Data.ActionName | Should -Be 'Set incident status to Resolved'
        }
    }

    It 'adds ResolvingComment to selected incident when property is missing' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('UpdateIncidentStatus')
            $context.Selection.Incident = [pscustomobject]@{
                IncidentId = 'inc-3b'
                Status     = 'active'
            }

            Mock Update-MgSecurityIncident {
                $script:lastBody = $BodyParameter
                [pscustomobject]@{ Id = $IncidentId; Status = $BodyParameter.status }
            }

            $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-3b' -Status 'Resolved' -SkipConfirmation

            $result.Success | Should -BeTrue
            $context.Selection.Incident.PSObject.Properties.Name | Should -Contain 'ResolvingComment'
            $context.Selection.Incident.ResolvingComment | Should -Be 'Incident resolved by current user using PwshXDRSpectre.'
        }
    }

    It 'uses mail then user principal name when assigning to me' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('AssignIncident')
            $context.Session.Analyst = [pscustomobject]@{
                Mail = ''
                UserPrincipalName = 'analyst@contoso.com'
            }

            Mock Update-MgSecurityIncident {
                $script:lastBody = $BodyParameter
                [pscustomobject]@{ Id = $IncidentId; AssignedTo = $BodyParameter.assignedTo }
            }

            $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-4' -AssignToMe -SkipConfirmation

            $result.Success | Should -BeTrue
            $script:lastBody.assignedTo | Should -Be 'analyst@contoso.com'
        }
    }

    It 'fails closed when incident status capability is missing' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'

            $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-5' -Status 'Active' -SkipConfirmation

            $result.Success | Should -BeFalse
            $result.Message | Should -Be 'Capability not available: UpdateIncidentStatus'
        }
    }

    It 'fails closed for invalid incident status policy values before Graph mutation' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
            $context.Capabilities.IncidentActions = @('UpdateIncidentStatus')

            $policy = Get-XdrTriagePolicy
            $invalidPolicy = $policy | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $invalidPolicy.incidentStatusMap = @($invalidPolicy.incidentStatusMap | Where-Object { $_.label -ne 'Active' })

            Mock Update-MgSecurityIncident {
                throw 'Graph mutation should not run for invalid policy values.'
            }

            { Set-XdrIncidentTriage -Context $context -IncidentId 'inc-invalid' -Status 'Active' -SkipConfirmation -Policy $invalidPolicy } | Should -Throw "Unknown triage value 'Active' for map 'incidentStatusMap'"
            Assert-MockCalled Update-MgSecurityIncident -Times 0 -Exactly
        }
    }

    Context 'AssignedTo parameter validation' {
        It 'accepts a valid UPN as AssignedTo' {
            InModuleScope PwshXDRSpectre {
                $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
                $context.Capabilities.IncidentActions = @('AssignIncident')

                Mock Update-MgSecurityIncident {
                    $script:lastBody = $BodyParameter
                    [pscustomobject]@{ Id = $IncidentId; AssignedTo = $BodyParameter.assignedTo }
                }

                $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-val-1' -AssignedTo 'analyst@contoso.com' -SkipConfirmation

                $result.Success | Should -BeTrue
                $script:lastBody.assignedTo | Should -Be 'analyst@contoso.com'
            }
        }

        It 'rejects a plain username without a domain' {
            InModuleScope PwshXDRSpectre {
                $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'

                { Set-XdrIncidentTriage -Context $context -IncidentId 'inc-val-2' -AssignedTo 'notanemail' -SkipConfirmation } |
                    Should -Throw '*AssignedTo must be a valid email address or UPN*'
            }
        }

        It 'rejects a value missing the TLD segment' {
            InModuleScope PwshXDRSpectre {
                $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'

                { Set-XdrIncidentTriage -Context $context -IncidentId 'inc-val-3' -AssignedTo 'analyst@contoso' -SkipConfirmation } |
                    Should -Throw '*AssignedTo must be a valid email address or UPN*'
            }
        }

        It 'bypasses AssignedTo validation when using AssignToMe' {
            InModuleScope PwshXDRSpectre {
                $context = New-XdrRuntimeContext -TenantId 'tenant-1' -ClientId 'client-1'
                $context.Capabilities.IncidentActions = @('AssignIncident')
                $context.Session.Analyst = [pscustomobject]@{
                    Mail              = 'me@contoso.com'
                    UserPrincipalName = 'me@contoso.com'
                    DisplayName       = 'Me'
                }

                Mock Update-MgSecurityIncident {
                    $script:lastBody = $BodyParameter
                    [pscustomobject]@{ Id = $IncidentId; AssignedTo = $BodyParameter.assignedTo }
                }

                # AssignToMe resolves identity internally; AssignedTo is never supplied by the caller
                $result = Set-XdrIncidentTriage -Context $context -IncidentId 'inc-val-4' -AssignToMe -SkipConfirmation

                $result.Success | Should -BeTrue
                $script:lastBody.assignedTo | Should -Be 'me@contoso.com'
            }
        }
    }
    
    Context 'comment-based help' {
        It 'has a Synopsis' {
            (Get-Help Set-XdrIncidentTriage).Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'has a Description' {
            (Get-Help Set-XdrIncidentTriage).Description | Should -Not -BeNullOrEmpty
        }
    }
}