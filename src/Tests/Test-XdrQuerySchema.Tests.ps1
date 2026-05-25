BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Test-XdrQuerySchema' {
    It 'accepts a valid query definition' {
        InModuleScope PwshXDRSpectre {
            $query = [pscustomobject]@{
                id              = 'user-signin-anomalies'
                name            = 'User Sign-In Anomalies'
                description     = 'Risk sign-in events for the selected user.'
                requiredContext = @('UserId')
                parameters      = @(
                    [pscustomobject]@{
                        name           = 'UserId'
                        contextBinding = 'UserId'
                        description    = 'Selected user identifier'
                    },
                    [pscustomobject]@{
                        name           = 'LookbackDays'
                        contextBinding = $null
                        defaultValue   = '7'
                        description    = 'Days to look back'
                    }
                )
                kql             = "AADSignInEventsBeta | where AccountObjectId == '{{UserId}}' | where Timestamp > ago({{LookbackDays}}d)"
                displayColumns  = @('Timestamp', 'AccountObjectId')
                tags            = @('identity')
            }

            Test-XdrQuerySchema -Query $query -Catalog @($query) -Source 'valid.json' | Should -BeTrue
        }
    }

    It 'rejects missing required fields' {
        InModuleScope PwshXDRSpectre {
            $query = [pscustomobject]@{
                id              = 'user-signin-anomalies'
                name            = 'User Sign-In Anomalies'
                requiredContext = @('UserId')
                parameters      = @()
                kql             = 'AADSignInEventsBeta'
                displayColumns  = @('Timestamp')
            }

            { Test-XdrQuerySchema -Query $query -Catalog @($query) -Source 'missing-description.json' } | Should -Throw "*Missing required field 'description'*"
        }
    }

    It 'rejects duplicate query ids across the catalog' {
        InModuleScope PwshXDRSpectre {
            $queryA = [pscustomobject]@{
                id              = 'duplicate-id'
                name            = 'First Query'
                description     = 'First description'
                requiredContext = @('IncidentId')
                parameters      = @(
                    [pscustomobject]@{
                        name           = 'IncidentId'
                        contextBinding = 'IncidentId'
                        description    = 'Incident id'
                    }
                )
                kql             = "SecurityIncident | where IncidentId == '{{IncidentId}}'"
                displayColumns  = @('IncidentId')
            }
            $queryB = [pscustomobject]@{
                id              = 'duplicate-id'
                name            = 'Second Query'
                description     = 'Second description'
                requiredContext = @('IncidentId')
                parameters      = @(
                    [pscustomobject]@{
                        name           = 'IncidentId'
                        contextBinding = 'IncidentId'
                        description    = 'Incident id'
                    }
                )
                kql             = "AlertInfo | where IncidentId == '{{IncidentId}}'"
                displayColumns  = @('IncidentId')
            }

            { Test-XdrQuerySchema -Query $queryA -Catalog @($queryA, $queryB) -Source 'duplicate-a.json' } | Should -Throw "*Duplicate query id 'duplicate-id'*"
        }
    }

    It 'rejects placeholders that do not have matching parameter definitions' {
        InModuleScope PwshXDRSpectre {
            $query = [pscustomobject]@{
                id              = 'orphan-placeholder'
                name            = 'Orphan Placeholder'
                description     = 'Invalid query for schema test'
                requiredContext = @('IncidentId')
                parameters      = @(
                    [pscustomobject]@{
                        name           = 'IncidentId'
                        contextBinding = 'IncidentId'
                        description    = 'Incident id'
                    }
                )
                kql             = "SecurityIncident | where IncidentId == '{{IncidentId}}' | where Title contains '{{SearchTerm}}'"
                displayColumns  = @('IncidentId')
            }

            { Test-XdrQuerySchema -Query $query -Catalog @($query) -Source 'orphan.json' } | Should -Throw "*placeholder 'SearchTerm'*"
        }
    }
}