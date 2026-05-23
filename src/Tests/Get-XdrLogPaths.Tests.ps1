BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrLogPaths' {
    It 'returns tracked existing absolute log paths without duplicates by default' {
        InModuleScope PwshXDRSpectre {
            $defaultLogRoot = [System.IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PwshXDRSpectre'))
            $trackedLogRegistryPath = Join-Path $defaultLogRoot 'tracked-log-paths.txt'
            $trackedLogDirectory = Split-Path -Parent $trackedLogRegistryPath
            $originalRegistryContent = if (Test-Path -LiteralPath $trackedLogRegistryPath) {
                [System.IO.File]::ReadAllText($trackedLogRegistryPath)
            }
            else {
                $null
            }

            try {
                if (-not [string]::IsNullOrWhiteSpace($trackedLogDirectory)) {
                    New-Item -ItemType Directory -Path $trackedLogDirectory -Force | Out-Null
                }

                $logPathOne = Join-Path $TestDrive 'one.log'
                $logPathTwo = Join-Path $TestDrive 'two.log'
                Set-Content -LiteralPath $logPathOne -Value 'one' -Encoding utf8
                Set-Content -LiteralPath $logPathTwo -Value 'two' -Encoding utf8
                Set-Content -LiteralPath $trackedLogRegistryPath -Value @($logPathOne, $logPathOne, $logPathTwo) -Encoding utf8

                $trackedPaths = @(Get-XdrLogPaths)

                $trackedPaths.Count | Should -Be 2
                $trackedPaths | Should -Contain $logPathOne
                $trackedPaths | Should -Contain $logPathTwo
            }
            finally {
                if ($null -eq $originalRegistryContent) {
                    Remove-Item -LiteralPath $trackedLogRegistryPath -Force -ErrorAction SilentlyContinue
                }
                else {
                    [System.IO.File]::WriteAllText($trackedLogRegistryPath, $originalRegistryContent)
                }
            }
        }
    }

    It 'omits missing paths by default' {
        InModuleScope PwshXDRSpectre {
            $defaultLogRoot = [System.IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PwshXDRSpectre'))
            $trackedLogRegistryPath = Join-Path $defaultLogRoot 'tracked-log-paths.txt'
            $trackedLogDirectory = Split-Path -Parent $trackedLogRegistryPath
            $originalRegistryContent = if (Test-Path -LiteralPath $trackedLogRegistryPath) {
                [System.IO.File]::ReadAllText($trackedLogRegistryPath)
            }
            else {
                $null
            }

            try {
                if (-not [string]::IsNullOrWhiteSpace($trackedLogDirectory)) {
                    New-Item -ItemType Directory -Path $trackedLogDirectory -Force | Out-Null
                }

                $existingLogPath = Join-Path $TestDrive 'existing.log'
                $missingLogPath = Join-Path $TestDrive 'missing.log'
                Set-Content -LiteralPath $existingLogPath -Value 'hello' -Encoding utf8
                Set-Content -LiteralPath $trackedLogRegistryPath -Value @($existingLogPath, $missingLogPath) -Encoding utf8

                $trackedPaths = @(Get-XdrLogPaths)

                $trackedPaths.Count | Should -Be 1
                $trackedPaths[0] | Should -Be $existingLogPath
            }
            finally {
                if ($null -eq $originalRegistryContent) {
                    Remove-Item -LiteralPath $trackedLogRegistryPath -Force -ErrorAction SilentlyContinue
                }
                else {
                    [System.IO.File]::WriteAllText($trackedLogRegistryPath, $originalRegistryContent)
                }
            }
        }
    }

    It 'includes missing tracked paths when IncludeMissing is requested' {
        InModuleScope PwshXDRSpectre {
            $defaultLogRoot = [System.IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PwshXDRSpectre'))
            $trackedLogRegistryPath = Join-Path $defaultLogRoot 'tracked-log-paths.txt'
            $trackedLogDirectory = Split-Path -Parent $trackedLogRegistryPath
            $originalRegistryContent = if (Test-Path -LiteralPath $trackedLogRegistryPath) {
                [System.IO.File]::ReadAllText($trackedLogRegistryPath)
            }
            else {
                $null
            }

            try {
                if (-not [string]::IsNullOrWhiteSpace($trackedLogDirectory)) {
                    New-Item -ItemType Directory -Path $trackedLogDirectory -Force | Out-Null
                }

                $existingLogPath = Join-Path $TestDrive 'existing.log'
                $missingLogPath = Join-Path $TestDrive 'missing.log'
                Set-Content -LiteralPath $existingLogPath -Value 'hello' -Encoding utf8
                Set-Content -LiteralPath $trackedLogRegistryPath -Value @($existingLogPath, $missingLogPath) -Encoding utf8

                $trackedPaths = @(Get-XdrLogPaths -IncludeMissing)

                $trackedPaths.Count | Should -Be 2
                $trackedPaths | Should -Contain $existingLogPath
                $trackedPaths | Should -Contain $missingLogPath
            }
            finally {
                if ($null -eq $originalRegistryContent) {
                    Remove-Item -LiteralPath $trackedLogRegistryPath -Force -ErrorAction SilentlyContinue
                }
                else {
                    [System.IO.File]::WriteAllText($trackedLogRegistryPath, $originalRegistryContent)
                }
            }
        }
    }
}