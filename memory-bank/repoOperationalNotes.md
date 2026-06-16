# Repo Operational Notes

## Source
Imported and normalized from `docs/copilot-memory-export.md` on 2026-06-16.

## Logging
- Dashboard and tracked log registry entries are stored at `%LOCALAPPDATA%\PwshXDRSpectre\tracked-log-paths.txt`.
- `Get-XdrLogPaths` returns existing tracked files by default.
- Use `Get-XdrLogPaths -IncludeMissing` to inspect stale historical entries.
- Default dashboard logs created with `Start-PwshXdrLiveDashboard -WithLogs` should use timestamped `.log` filenames under `%LOCALAPPDATA%\PwshXDRSpectre`.
- For alert-cache troubleshooting, correlate `Alert preload job completed` entries, including `AlertCount` and `Message`, with `Alert cache restore hit/miss` entries to separate empty Graph data from cache or renderer drift.

## PowerShell and TUI Pitfalls
- Do not invoke state-mutating PowerShell scriptblocks with `&` when the caller depends on outer UI or render state.
- Keep physical layout slot ids separate from logical workflow panel names.
- Prefer `.Keys -contains <name>` over `.Contains(<name>)` for nested Graph or API payloads that may be dictionaries or ordered dictionaries.
- Debug keyboard-navigation issues in this order: key capture, logical panel routing, then selected-object state versus index state.
- When invoking module scriptblocks or thread-job callbacks with multiple arguments, do not place commas after the closing `}`.
- Keep network-bound hunting query work off the live dashboard loop and fold completed results back into UI state from the main loop.
- Cache expensive selection-driven results by stable item key and rebind visible state from the cache.
- Query-result cache keys must include the resolved parameter snapshot, such as `IncidentId`, `DeviceId`, and `UserId`, not just the query id.
- Keep the initial incident list lightweight; do not expand alerts in the initial list request.
- If lightweight incident data omits alert references, lazily fetch the selected incident with `Get-MgSecurityIncident -IncidentId <id> -ExpandProperty 'alerts'`.
- Do not return full Microsoft Graph SDK objects from live-dashboard background jobs; project lean view models instead.
- Keep dashboard startup lazy. Avoid fan-out alert preloading and defer entity extraction until the user opens the Entities workflow.
- Poll keys before any loading or authentication branch can `continue`, and keep a RawUI fallback in addition to `[Console]::KeyAvailable`.
- Alert loading should be explicit, not automatic on incident selection, startup, or plain tab navigation.
- Throttle the live dashboard loop at the top of each iteration, not only after render.
- Incident-list loading must be active-tab independent so background job processing and help updates continue even while placeholder tabs are visible.
- Keep the entire dashboard tick inside the `while ($true)` loop.
- Avoid hidden workflow modes that render under the wrong top-level tab. Active top-level tab should be the source of truth.
- For alert cache and visible-panel synchronization, compare a stable alert-list signature such as id, status, severity, and title.
- When extracting stateful dashboard closures into private helpers, pass mutated caller variables as `[ref]` parameters and update `.Value`.
- Spectre `Panel` objects are effectively immutable for child layout swaps. Rebuild the root layout and reattach it with `Update-XdrLiveOuterTabs`.
- For Ctrl and Alt shortcuts, do not rely only on `ConsoleKeyInfo.KeyChar`; match the physical key as well, preferably through `Test-XdrConsoleShortcut`.

## Testing
- PowerShell tests in this repo validate reliably via `Invoke-Pester -Path "src/Tests/<file>.ps1"`.
- The generic test runner may report no tests found for this repo.
- Phase 4 query catalog and execution changes validate reliably with the focused `Invoke-Pester` slice covering:
  - `src/Tests/Invoke-XdrHuntingQuery.Tests.ps1`
  - `src/Tests/Add-XdrQueryRun.Tests.ps1`
  - `src/Tests/New-XdrRuntimeContext.Tests.ps1`
  - `src/Tests/Get-XdrQueryCatalog.Tests.ps1`
  - `src/Tests/Test-XdrQuerySchema.Tests.ps1`
  - `src/Tests/Resolve-XdrQueryParameters.Tests.ps1`
  - `src/Tests/Invoke-XdrQueryInterpolation.Tests.ps1`
- For hunting-mode input bugs, temporary help-panel diagnostics for last key, logical panel name, query index, and selected query id are a fast way to separate input-capture failures from stale render-state issues.
