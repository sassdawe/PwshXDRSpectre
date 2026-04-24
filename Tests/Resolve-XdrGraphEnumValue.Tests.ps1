BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Resolve-XdrGraphEnumValue' {
    It 'resolves incident status display values to graph values' {
        InModuleScope PwshXDRSpectre {
            Resolve-XdrGraphEnumValue -MapName 'incidentStatusMap' -DisplayValue 'In progress' | Should -Be 'inProgress'
        }
    }
}