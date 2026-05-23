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

    if (-not [System.IO.Path]::IsPathRooted($LogPath)) {
        $defaultLogRoot = [System.IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PwshXDRSpectre'))
        $resolvedLogPath = [System.IO.Path]::GetFullPath((Join-Path $defaultLogRoot $LogPath))
        $defaultLogRootPrefix = $defaultLogRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

        if (-not $resolvedLogPath.StartsWith($defaultLogRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Warning -Message "Rejected relative log path outside the dashboard log root: $LogPath"
            return
        }

        $LogPath = $resolvedLogPath
    }

    $directory = Split-Path -Parent $LogPath
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force -ErrorAction SilentlyContinue | Out-Null
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