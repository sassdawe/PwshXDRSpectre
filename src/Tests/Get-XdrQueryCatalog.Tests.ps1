BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrQueryCatalog' {
    It 'loads all starter query definitions from the default catalog path' {
        InModuleScope PwshXDRSpectre {
            $catalog = @(Get-XdrQueryCatalog)

            $catalog.Count | Should -Be 3
            @($catalog | ForEach-Object { [string]$_.id }) | Should -Be @(
                'device-process-tree',
                'incident-related-alerts',
                'user-signin-anomalies'
            )
        }
    }

    It 'throws actionable parse errors that include the failing file name' {
        InModuleScope PwshXDRSpectre {
            $catalogPath = Join-Path $TestDrive 'queries'
            $null = New-Item -ItemType Directory -Path $catalogPath -Force
            '{ bad json' | Set-Content -Path (Join-Path $catalogPath 'broken.json')

            { Get-XdrQueryCatalog -Path $catalogPath } | Should -Throw 'Failed to parse query catalog file ''broken.json''*'
        }
    }
}