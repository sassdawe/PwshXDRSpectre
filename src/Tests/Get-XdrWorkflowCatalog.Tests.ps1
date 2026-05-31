BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrWorkflowCatalog' {
    It 'loads bundled workflow definitions' {
        InModuleScope PwshXDRSpectre {
            $catalog = @(Get-XdrWorkflowCatalog)

            $catalog.Count | Should -BeGreaterThan 0
            @($catalog.id) | Should -Contain 'high-severity-incident-review'
            @($catalog.id) | Should -Contain 'suspicious-signin-review'
        }
    }

    It 'throws a parse error for invalid JSON' {
        InModuleScope PwshXDRSpectre {
            $catalogPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $catalogPath | Out-Null
            Set-Content -Path (Join-Path $catalogPath 'broken.json') -Value '{ invalid json'

            try {
                { Get-XdrWorkflowCatalog -Path $catalogPath } | Should -Throw "Failed to parse workflow catalog file 'broken.json'*"
            }
            finally {
                Remove-Item -Path $catalogPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
