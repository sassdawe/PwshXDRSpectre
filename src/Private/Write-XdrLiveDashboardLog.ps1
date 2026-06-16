function Write-XdrLiveDashboardLog {
    <#
    .SYNOPSIS
    Writes a dashboard log entry using cross-runspace synchronization.

    .DESCRIPTION
    Appends a single line to the dashboard log file while protecting writes with
    a named mutex to avoid line interleaving when multiple thread jobs log
    concurrently.

    .PARAMETER LogPath
    Target log file path.

    .PARAMETER Message
    Log message text.

    .PARAMETER Level
    Log level tag.

    .OUTPUTS
    None

    .EXAMPLE
    Write-XdrLiveDashboardLog -LogPath $logPath -Message 'Incident load job started.' -Level 'INFO'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$LogPath,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$Level = 'INFO'
    )

    if ([string]::IsNullOrWhiteSpace($LogPath) -or [string]::IsNullOrWhiteSpace($Message)) {
        return
    }

    $defaultLogRoot = [System.IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PwshXDRSpectre'))
    $trackedLogRegistryPath = Join-Path $defaultLogRoot 'tracked-log-paths.txt'
    $pathComparison = if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    $testRelativeLogPath = {
        param(
            [string]$ResolvedLogPath,
            [string]$RelativeLogPath
        )

        $defaultLogRootPrefix = $defaultLogRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $ResolvedLogPath.StartsWith($defaultLogRootPrefix, $pathComparison)) {
            return $false
        }

        $resolvedLogDirectory = Split-Path -Parent $ResolvedLogPath
        if (-not [string]::IsNullOrWhiteSpace($resolvedLogDirectory)) {
            $relativeLogDirectory = [System.IO.Path]::GetRelativePath($defaultLogRoot, $resolvedLogDirectory)
            $currentDirectory = $defaultLogRoot
            foreach ($segment in ($relativeLogDirectory -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne '.' })) {
                $currentDirectory = Join-Path $currentDirectory $segment
                if (Test-Path -LiteralPath $currentDirectory) {
                    $currentItem = Get-Item -LiteralPath $currentDirectory -Force -ErrorAction SilentlyContinue
                    if ($null -ne $currentItem -and $currentItem.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
                        return $false
                    }
                }
            }
        }

        return $true
    }

    if (-not [System.IO.Path]::IsPathRooted($LogPath)) {
        $relativeLogPath = $LogPath
        if (($relativeLogPath -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -contains '..') {
            return
        }
        $resolvedLogPath = [System.IO.Path]::GetFullPath((Join-Path $defaultLogRoot $LogPath))
        if (-not (& $testRelativeLogPath $resolvedLogPath $relativeLogPath)) {
            return
        }
        $LogPath = $resolvedLogPath
    }

    $directory = Split-Path -Parent $LogPath
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force -ErrorAction SilentlyContinue | Out-Null
    }

    $registerTrackedLogPath = {
        param([string]$ResolvedLogPath)

        if ([string]::IsNullOrWhiteSpace($ResolvedLogPath)) {
            return
        }

        $registryDirectory = Split-Path -Parent $trackedLogRegistryPath
        if (-not [string]::IsNullOrWhiteSpace($registryDirectory)) {
            New-Item -ItemType Directory -Path $registryDirectory -Force -ErrorAction SilentlyContinue | Out-Null
        }

        $registryHashBytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($trackedLogRegistryPath.ToLowerInvariant()))
        $registryHash = [Convert]::ToHexString($registryHashBytes).Substring(0, 24)
        $registryMutexName = "PwshXdrSpectreTrackedLogs_$registryHash"
        $registryMutex = $null
        $registryLockTaken = $false

        try {
            $registryMutex = [System.Threading.Mutex]::new($false, $registryMutexName)
            try {
                $registryLockTaken = $registryMutex.WaitOne(2000)
            }
            catch [System.Threading.AbandonedMutexException] {
                $registryLockTaken = $true
            }

            if (-not $registryLockTaken) {
                return
            }

            $trackedPaths = if (Test-Path -LiteralPath $trackedLogRegistryPath) {
                @(Get-Content -LiteralPath $trackedLogRegistryPath -ErrorAction SilentlyContinue)
            }
            else {
                @()
            }

            $alreadyTracked = $false
            foreach ($trackedPath in $trackedPaths) {
                if ([string]::Equals([string]$trackedPath, $ResolvedLogPath, $pathComparison)) {
                    $alreadyTracked = $true
                    break
                }
            }

            if (-not $alreadyTracked) {
                Add-Content -LiteralPath $trackedLogRegistryPath -Value $ResolvedLogPath -Encoding utf8 -ErrorAction SilentlyContinue
            }
        }
        finally {
            if ($registryLockTaken -and $null -ne $registryMutex) {
                $registryMutex.ReleaseMutex() | Out-Null
            }

            if ($null -ne $registryMutex) {
                $registryMutex.Dispose()
            }
        }
    }

    $hashBytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($LogPath.ToLowerInvariant()))
    $hash = [Convert]::ToHexString($hashBytes).Substring(0, 24)
    $mutexName = "PwshXdrSpectreLog_$hash"
    $mutex = $null
    $lockTaken = $false

    try {
        $mutex = [System.Threading.Mutex]::new($false, $mutexName)
        try {
            $lockTaken = $mutex.WaitOne(2000)
        }
        catch [System.Threading.AbandonedMutexException] {
            # Previous owner exited without releasing; we now own the mutex
            $lockTaken = $true
        }
        if (-not $lockTaken) {
            return
        }

        $logEntry = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level.ToUpperInvariant(), $Message
        Add-Content -LiteralPath $LogPath -Value $logEntry -Encoding utf8 -ErrorAction SilentlyContinue
        & $registerTrackedLogPath $LogPath
    }
    finally {
        if ($lockTaken -and $null -ne $mutex) {
            $mutex.ReleaseMutex() | Out-Null
        }

        if ($null -ne $mutex) {
            $mutex.Dispose()
        }
    }
}