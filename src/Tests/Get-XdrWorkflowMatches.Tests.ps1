BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrWorkflowMatches' {
    It 'matches workflow conditions against incident severity' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext
            $context.Selection.Incident = [pscustomobject]@{ Severity = 'High'; Status = 'Active'; SystemTags = @(); CustomTags = @() }
            $workflow = [pscustomobject]@{
                id          = 'high-severity'
                name        = 'High Severity'
                description = 'High severity workflow.'
                match       = 'all'
                conditions  = @([pscustomobject]@{ field = 'severity'; operator = 'equals'; value = 'high' })
                steps       = @([pscustomobject]@{ title = 'Review'; guidance = 'Review incident.' })
            }

            $matches = @(Get-XdrWorkflowMatches -Catalog @($workflow) -Context $context)

            $matches.Count | Should -Be 1
            $matches[0].TriggerReason | Should -Match 'severity equals high'
        }
    }

    It 'matches workflow conditions against alert category and entity type' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext
            $context.Selection.Incident = [pscustomobject]@{ SystemTags = @(); CustomTags = @() }
            $context.Selection.Alert = [pscustomobject]@{ Category = 'SuspiciousSignIn'; Tags = @() }
            $context.Selection.Entity = [pscustomobject]@{ EntityType = 'User' }
            $workflow = [pscustomobject]@{
                id          = 'signin'
                name        = 'Sign-in'
                description = 'Sign-in workflow.'
                match       = 'all'
                conditions  = @(
                    [pscustomobject]@{ field = 'category'; operator = 'contains'; value = 'sign' },
                    [pscustomobject]@{ field = 'entityType'; operator = 'equals'; value = 'user' }
                )
                steps       = @([pscustomobject]@{ title = 'Review'; guidance = 'Review user.' })
            }

            @(Get-XdrWorkflowMatches -Catalog @($workflow) -Context $context).Count | Should -Be 1
        }
    }

    It 'does not match unrelated conditions' {
        InModuleScope PwshXDRSpectre {
            $context = New-XdrRuntimeContext
            $context.Selection.Incident = [pscustomobject]@{ Severity = 'Low'; SystemTags = @(); CustomTags = @() }
            $workflow = [pscustomobject]@{
                id          = 'high-severity'
                name        = 'High Severity'
                description = 'High severity workflow.'
                conditions  = @([pscustomobject]@{ field = 'severity'; operator = 'equals'; value = 'high' })
                steps       = @([pscustomobject]@{ title = 'Review'; guidance = 'Review incident.' })
            }

            @(Get-XdrWorkflowMatches -Catalog @($workflow) -Context $context).Count | Should -Be 0
        }
    }
}
