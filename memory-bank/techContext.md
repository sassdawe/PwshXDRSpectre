# Tech Context

## Stack
- PowerShell 7 module
- PwshSpectreConsole for terminal UI rendering
- Microsoft.Graph.Authentication and Microsoft.Graph.Security for Defender XDR access
- Pester v5 for tests
- GitHub Actions for CI, release, security scanning, and dependency review

## Repository Structure
- `src/` contains the module manifest, module loader, private helpers, public entry points, and tests.
- `queries/` contains repository-backed hunting query definitions in JSON.
- `plans/` contains phased implementation planning.
- `docs/` contains supporting documentation.
- `.github/` contains workflows, skills, and policy documents.

## Important Entry Points
- Module loader: `src/PwshXDRSpectre.psm1`
- Module manifest: `src/PwshXDRSpectre.psd1`
- Main dashboard entry point: `Start-PwshXdrLiveDashboard`

## Validation Commands
```powershell
Invoke-Pester -Path ./src/Tests -Output Detailed
Test-ModuleManifest -Path ./src/PwshXDRSpectre.psd1
```

## Repo-Specific Testing Notes
- Focused PowerShell tests validate reliably with explicit `Invoke-Pester -Path "src/Tests/<file>.ps1"` usage.
- Generic test discovery helpers may miss Pester coverage in this repo.
- When tooling misses tests, run PowerShell 7 directly from `src/` with `& 'C:\Program Files\PowerShell\7.6\7\pwsh.exe' -NoLogo -NoProfile -Command "Invoke-Pester -Path './Tests/<file>.Tests.ps1'"`.

## Repo-Specific PowerShell Notes
- Avoid invoking state-mutating scriptblocks with `&` when outer UI state must be updated.
- Use `[ref]` parameters when extracting helpers that mutate caller-owned dashboard state.
- Keep network-bound hunting and Graph work in background jobs and merge results back into UI state from the main loop.

## Logging and Diagnostics
- Tracked dashboard log registry entries live at `%LOCALAPPDATA%\PwshXDRSpectre\tracked-log-paths.txt`.
- `Get-XdrLogPaths` returns existing tracked files by default; use `Get-XdrLogPaths -IncludeMissing` to inspect stale historical entries.
- `Start-PwshXdrLiveDashboard -WithLogs` should create timestamped `.log` files under `%LOCALAPPDATA%\PwshXDRSpectre`.
