BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Test-XdrWorkflowSchema' {
    It 'accepts a valid workflow definition' {
        InModuleScope PwshXDRSpectre {
            $workflow = [pscustomobject]@{
                id              = 'high-severity-review'
                name            = 'High Severity Review'
                description     = 'Investigate high severity incidents.'
                match           = 'any'
                requiredContext = @('IncidentId')
                conditions      = @(
                    [pscustomobject]@{ field = 'severity'; operator = 'equals'; value = 'high' }
                )
                steps           = @(
                    [pscustomobject]@{ title = 'Review incident'; guidance = 'Review incident context.'; evidence = @('Incident id') }
                )
                tags            = @('incident')
            }

            Test-XdrWorkflowSchema -Workflow $workflow -Catalog @($workflow) -Source 'valid.json' | Should -BeTrue
        }
    }

    It 'rejects missing required fields' {
        InModuleScope PwshXDRSpectre {
            $workflow = [pscustomobject]@{
                id          = 'missing-description'
                name        = 'Missing Description'
                conditions  = @([pscustomobject]@{ field = 'severity'; operator = 'equals'; value = 'high' })
                steps       = @([pscustomobject]@{ title = 'Review incident'; guidance = 'Review incident context.' })
            }

            { Test-XdrWorkflowSchema -Workflow $workflow -Catalog @($workflow) -Source 'missing-description.json' } | Should -Throw "*Missing required field 'description'*"
        }
    }

    It 'rejects invalid condition fields' {
        InModuleScope PwshXDRSpectre {
            $workflow = [pscustomobject]@{
                id          = 'invalid-field'
                name        = 'Invalid Field'
                description = 'Invalid workflow.'
                conditions  = @([pscustomobject]@{ field = 'unknown'; operator = 'equals'; value = 'high' })
                steps       = @([pscustomobject]@{ title = 'Review incident'; guidance = 'Review incident context.' })
            }

            { Test-XdrWorkflowSchema -Workflow $workflow -Catalog @($workflow) -Source 'invalid-field.json' } | Should -Throw "*Invalid condition field 'unknown'*"
        }
    }

    It 'rejects duplicate workflow ids across the catalog' {
        InModuleScope PwshXDRSpectre {
            $workflowA = [pscustomobject]@{
                id          = 'duplicate-workflow'
                name        = 'First Workflow'
                description = 'First workflow.'
                conditions  = @([pscustomobject]@{ field = 'severity'; operator = 'equals'; value = 'high' })
                steps       = @([pscustomobject]@{ title = 'Review incident'; guidance = 'Review incident context.' })
            }
            $workflowB = [pscustomobject]@{
                id          = 'duplicate-workflow'
                name        = 'Second Workflow'
                description = 'Second workflow.'
                conditions  = @([pscustomobject]@{ field = 'status'; operator = 'equals'; value = 'active' })
                steps       = @([pscustomobject]@{ title = 'Review alert'; guidance = 'Review alert context.' })
            }

            { Test-XdrWorkflowSchema -Workflow $workflowA -Catalog @($workflowA, $workflowB) -Source 'duplicate-a.json' } | Should -Throw "*Duplicate workflow id 'duplicate-workflow'*"
        }
    }
}
