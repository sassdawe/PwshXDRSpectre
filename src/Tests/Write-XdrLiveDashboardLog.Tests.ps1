BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Write-XdrLiveDashboardLog' {
    It 'does not throw when LogPath is an empty string' {
        InModuleScope PwshXDRSpectre {
            { Write-XdrLiveDashboardLog -LogPath '' -Message 'hello' } | Should -Not -Throw
        }
    }

    It 'does not throw when LogPath is null' {
        InModuleScope PwshXDRSpectre {
            { Write-XdrLiveDashboardLog -LogPath $null -Message 'hello' } | Should -Not -Throw
        }
    }

    It 'does not throw when LogPath is whitespace only' {
        InModuleScope PwshXDRSpectre {
            { Write-XdrLiveDashboardLog -LogPath '   ' -Message 'hello' } | Should -Not -Throw
        }
    }

    It 'does not throw when Message is whitespace only' {
        InModuleScope PwshXDRSpectre {
            { Write-XdrLiveDashboardLog -LogPath (Join-Path $TestDrive 'test.log') -Message '   ' } | Should -Not -Throw
        }
    }

    It 'appends a log entry to the file' {
        InModuleScope PwshXDRSpectre {
            $logFile = Join-Path $TestDrive 'dashboard.log'
            Write-XdrLiveDashboardLog -LogPath $logFile -Message 'test message'
            $logFile | Should -Exist
            $content = Get-Content -LiteralPath $logFile -Raw
            $content | Should -Match 'test message'
        }
    }

    It 'uses INFO as the default log level' {
        InModuleScope PwshXDRSpectre {
            $logFile = Join-Path $TestDrive 'level-default.log'
            Write-XdrLiveDashboardLog -LogPath $logFile -Message 'default level'
            $content = Get-Content -LiteralPath $logFile -Raw
            $content | Should -Match '\[INFO\]'
        }
    }

    It 'writes a custom log level in the entry' {
        InModuleScope PwshXDRSpectre {
            $logFile = Join-Path $TestDrive 'level-warn.log'
            Write-XdrLiveDashboardLog -LogPath $logFile -Message 'warn message' -Level WARN
            $content = Get-Content -LiteralPath $logFile -Raw
            $content | Should -Match '\[WARN\]'
        }
    }

    It 'appends multiple entries without overwriting' {
        InModuleScope PwshXDRSpectre {
            $logFile = Join-Path $TestDrive 'multi.log'
            Write-XdrLiveDashboardLog -LogPath $logFile -Message 'entry one'
            Write-XdrLiveDashboardLog -LogPath $logFile -Message 'entry two'
            $lines = @(Get-Content -LiteralPath $logFile)
            $lines.Count | Should -Be 2
            $lines[0] | Should -Match 'entry one'
            $lines[1] | Should -Match 'entry two'
        }
    }

    It 'does not throw when the mutex has been abandoned by a previous holder' {
        InModuleScope PwshXDRSpectre {
            $logFile = Join-Path $TestDrive 'abandoned.log'
            $mutexAbandonTimeoutMs = 3000

            $hashBytes = [System.Security.Cryptography.SHA256]::HashData(
                [System.Text.Encoding]::UTF8.GetBytes($logFile.ToLowerInvariant())
            )
            $hash = [Convert]::ToHexString($hashBytes).Substring(0, 24)
            $mutexName = "PwshXdrSpectreLog_$hash"

            if (-not ([System.Management.Automation.PSTypeName]'PwshXdrTestMutexAbandoner').Type) {
                Add-Type -TypeDefinition @"
using System.Threading;
public static class PwshXdrTestMutexAbandoner {
    public static void Abandon(string mutexName, int timeoutMs) {
        var t = new Thread(() => {
            var m = new Mutex(false, mutexName);
            m.WaitOne();
        });
        t.IsBackground = true;
        t.Start();
        t.Join(timeoutMs);
    }
}
"@
            }

            [PwshXdrTestMutexAbandoner]::Abandon($mutexName, $mutexAbandonTimeoutMs)

            { Write-XdrLiveDashboardLog -LogPath $logFile -Message 'post-abandon' } | Should -Not -Throw
        }
    }

    It 'creates the log directory if it does not exist' {
        InModuleScope PwshXDRSpectre {
            $logFile = Join-Path $TestDrive 'subdir' 'nested.log'
            { Write-XdrLiveDashboardLog -LogPath $logFile -Message 'nested' } | Should -Not -Throw
            $logFile | Should -Exist
        }
    }

    It 'resolves relative log paths under local app data instead of the current directory' {
        InModuleScope PwshXDRSpectre {
            $relativeLogPath = '44'
            $expectedLogFile = [System.IO.Path]::GetFullPath((Join-Path (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PwshXDRSpectre') $relativeLogPath))

            if (Test-Path -LiteralPath $expectedLogFile) {
                Remove-Item -LiteralPath $expectedLogFile -Force -ErrorAction SilentlyContinue
            }

            Write-XdrLiveDashboardLog -LogPath $relativeLogPath -Message 'relative-path test'

            $expectedLogFile | Should -Exist
            Join-Path (Get-Location) $relativeLogPath | Should -Not -Exist

            Remove-Item -LiteralPath $expectedLogFile -Force -ErrorAction SilentlyContinue
        }
    }

    It 'tracks the absolute log path when a log entry is written' {
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

                $logFile = Join-Path $TestDrive 'tracked.log'
                Write-XdrLiveDashboardLog -LogPath $logFile -Message 'track me'

                $trackedEntries = @(Get-Content -LiteralPath $trackedLogRegistryPath -ErrorAction SilentlyContinue)
                $trackedEntries | Should -Contain $logFile
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

    It 'does not duplicate a tracked log path across multiple writes' {
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

                $logFile = Join-Path $TestDrive 'tracked-once.log'
                Write-XdrLiveDashboardLog -LogPath $logFile -Message 'first'
                Write-XdrLiveDashboardLog -LogPath $logFile -Message 'second'

                $trackedEntries = @(Get-Content -LiteralPath $trackedLogRegistryPath -ErrorAction SilentlyContinue | Where-Object { $_ -eq $logFile })
                $trackedEntries.Count | Should -Be 1
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

    It 'does not allow relative path traversal outside local app data' {
        InModuleScope PwshXDRSpectre {
            $relativeLogPath = Join-Path '..' 'escape.log'
            $defaultLogRoot = [System.IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PwshXDRSpectre'))
            $escapedLogFile = [System.IO.Path]::GetFullPath((Join-Path $defaultLogRoot $relativeLogPath))

            if (Test-Path -LiteralPath $escapedLogFile) {
                Remove-Item -LiteralPath $escapedLogFile -Force -ErrorAction SilentlyContinue
            }

            Write-XdrLiveDashboardLog -LogPath $relativeLogPath -Message 'traversal test'

            if (Test-Path -LiteralPath $escapedLogFile) {
                throw "Traversal path was unexpectedly created: $escapedLogFile"
            }
        }
    }
}
