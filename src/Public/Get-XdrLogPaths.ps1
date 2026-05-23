function Get-XdrLogPaths {
    <#
    .SYNOPSIS
    Returns tracked absolute paths for generated XDR log files.

    .DESCRIPTION
    Reads the module's tracked log registry and returns unique absolute log file
    paths that were previously written through Write-XdrLiveDashboardLog. The
    registry entries are stored in tracked-log-paths.txt under the module's
    local application data root, typically:
    %LOCALAPPDATA%\PwshXDRSpectre\tracked-log-paths.txt

    .PARAMETER IncludeMissing
    Includes tracked paths that no longer exist on disk.

    .OUTPUTS
    System.String

    .EXAMPLE
    Get-XdrLogPaths

    .EXAMPLE
    Get-XdrLogPaths -IncludeMissing

    .NOTES
    The tracked log registry file is stored at:
    %LOCALAPPDATA%\PwshXDRSpectre\tracked-log-paths.txt
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$IncludeMissing
    )

    $defaultLogRoot = [System.IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PwshXDRSpectre'))
    $trackedLogRegistryPath = Join-Path $defaultLogRoot 'tracked-log-paths.txt'

    if (-not (Test-Path -LiteralPath $trackedLogRegistryPath)) {
        return
    }

    $pathComparer = if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        [System.StringComparer]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparer]::Ordinal
    }

    $seenPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
    foreach ($trackedPath in @(Get-Content -LiteralPath $trackedLogRegistryPath -ErrorAction SilentlyContinue)) {
        $candidatePath = [string]$trackedPath
        if ([string]::IsNullOrWhiteSpace($candidatePath)) {
            continue
        }

        if (-not $IncludeMissing.IsPresent -and -not (Test-Path -LiteralPath $candidatePath)) {
            continue
        }

        if ($seenPaths.Add($candidatePath)) {
            $candidatePath
        }
    }
}