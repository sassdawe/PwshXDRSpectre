---
name: pwshxdrspectre-powershell
description: 'Repo-specific PowerShell and Spectre TUI conventions for the PwshXDRSpectre live dashboard. Use when editing src/Public/Start-PwshXdrLiveDashboard.ps1 or any src/Private/*.ps1, adjusting Graph/Microsoft.Graph data flow, wiring background ThreadJobs, sizing terminal panels with Spectre, handling Ctrl/Alt keyboard shortcuts, caching incident/alert/entity/query results, or composing parameter-aware cache keys. Captures empty-data binding rules, [ref] mutation patterns, lazy loading invariants, render-loop throttling, panel slot vs logical panel naming, and color/label conventions for tabs and the action panel.'
---

# PwshXDRSpectre PowerShell & TUI Conventions

Repo-specific authoring rules for the live dashboard and supporting cmdlets. Generic PowerShell guidance is in `.github/instructions/powershell.instructions.md` and is not repeated here.

## When to Use This Skill

- Editing `src/Public/Start-PwshXdrLiveDashboard.ps1`, `src/Public/*.ps1` or any `src/Private/*.ps1` files.
- Adding or refactoring functions that take Graph results (`Incidents`, `Alerts`, `Entities`)
- Wiring or completing background `ThreadJob` work and folding results back into UI state
- Adjusting Spectre layout, panel widths, color/border markup, or keyboard handling
- Designing or modifying caches keyed by incident, alert, entity, or query parameters

## Empty Graph Data Is Normal

Graph endpoints legitimately return `@()` and `''`. Functions fed from Graph must accept these:

- **Mandatory `[object[]]`** that may receive `@()` → add `[AllowEmptyCollection()]` and let `foreach` over `@($value)` no-op naturally.
- **Mandatory `[string]`** that may receive `''` (blank selection / no incident) → add `[AllowEmptyString()]` and return early with a logged skip and the function's neutral return value (e.g. `$false` for cache restore).
- Pair every relaxation with a regression test (see the `pwshxdrspectre-pester-tests` skill).

## State Mutation Across Helpers

- When extracting closures into private helpers that update outer dashboard state (selected item, preview, result, visible alerts), pass mutated callers as `[ref]` and assign through `.Value`. Plain parameters silently mutate copies.
- Do not invoke state-mutating script blocks with `&` from a child scope when the caller depends on outer variables for render state. Use current-scope execution so index changes and selected-object render state stay in sync.

## Live Dashboard Loop Discipline

- The whole tick must stay inside the `while ($true)` loop. Closing the loop too early hides job processing, key handling, and final rendering.
- **Throttle at the top** of each iteration, not only after render. Skipping render must not skip the throttle, or the loop spins thousands of iterations per second and starves Spectre and input.
- **Poll keys before any authentication/loading branch can `continue`.** Keep a RawUI fallback in addition to `[Console]::KeyAvailable`, otherwise the heartbeat updates while controls are ignored.
- **Incident list loading is active-tab independent.** Top-level tabs may render placeholders, but background incident jobs and the shared help panel must keep ticking on every loading branch.
- **Active tab is the source of truth** for mode-specific panels. Route shortcuts (e.g. `Alt+H`) through tab activation helpers so selection, help text, and render state stay aligned.

## Lazy Loading & Background Jobs

- Keep the initial incident list lightweight. **Never** call `Get-MgSecurityIncident -ExpandProperty Alerts` for the list view; it stalls heartbeat/render. Lazily expand alerts via `Get-MgSecurityIncident -IncidentId <id> -ExpandProperty 'alerts'` only for the selected incident.
- Alert loading must be explicit (`Enter` / Alt+L / Alt+Shift+L), never automatic on selection or startup. Tab switching and arrow navigation must not start Graph jobs.
- Avoid fan-out preloading and entity extraction at startup; even background jobs starve the TUI when several thread-job completions arrive together.
- Any network-bound hunting query work must run in a background job and fold results back into UI state from the main loop.
- **Project lean view models** out of `ThreadJob` results. Do not return full Microsoft Graph SDK objects; copy only needed fields (Evidence/Entities) so `Receive-Job` and rendering do not stall.
- When invoking module scriptblocks or thread-job callbacks with multiple arguments, **do not** put commas after the closing `}`; pass arguments positionally with spaces or use a single payload object. Commas have flattened arguments into malformed log paths in this repo.

## Caching

- Cache expensive results by a stable item key (incident id, query id) and let selection changes rebind the visible result from the cache. A single shared "current result" variable will make previously loaded data disappear on navigation.
- **Context-bound queries** must include the resolved parameter snapshot in the cache key (e.g. `IncidentId`, `DeviceId`, `UserId`), not just the query id. Otherwise switching incidents or entities reuses results from a different execution context.
- For alert visibility/cache sync, **incident id + count is not enough** to detect stale UI. Compare a stable alert-list signature (id/status/severity/title) so same-count cache replacements still rebind the rendered list.

## Spectre Layout & Rendering

- **Layout slots vs logical panels**: keep physical slot ids (`left_top`, `center_top`, `right_actions`) separate from workflow focus ids (`incident_list`, `alert_list`, `query_catalog`). Help text, diagnostics, and keyboard routing all key off the workflow id.
- Spectre `Panel` instances do not expose a mutable child-data property. To switch the dashboard layout shape, **rebuild the root layout, replace the dashboard frame panel, then call `Update-XdrLiveOuterTabs`** to reattach it to the screen layout.
- **Fixed-width text tables (incident list, alert list)**: derive title width from console width and current layout ratios; trim long titles with `...` before render. Static title widths cause line wrapping when the action panel toggles or the terminal narrows. Sev = 3, ID = 2 (incident list), Status = 6; Title takes whatever space remains.
- **Tab theme**: outer tabs are pure markup from `Get-XdrLiveOuterTabsHeader`. Inactive tabs use `deepskyblue1` to match the dashboard border accent; the active tab uses `orange1`.
- **Action panel labels**: keep verbose action names for policy/safety checks (`Set incident status to Active`), but shorten only the rendered/entry labels (`Set Inc. to Active`) to prevent wrapping in the right column.

## Keyboard Handling

- For Ctrl/Alt shortcuts, do not rely only on `ConsoleKeyInfo.KeyChar`; modified keys can arrive as control characters or empty chars. Match the physical `ConsoleKeyInfo.Key` as well, preferably through `Test-XdrConsoleShortcut`.
- For navigation bugs, add temporary help-panel diagnostics for last key, logical panel, query index, selected query id, and handled state. **Debug order**: input capture → logical panel routing → selected-object state vs index. This isolates input vs routing vs render bugs.

## Graph Payload Quirks

- Nested Graph/API payloads may arrive as `Hashtable`, `OrderedDictionary`, or `IDictionary`. Use `.Keys -contains <name>` rather than `.Contains(<name>)` to avoid runtime overload mismatches.

## Logging

- Tracked log registry: `%LOCALAPPDATA%\PwshXDRSpectre\tracked-log-paths.txt`. `Get-XdrLogPaths` returns existing tracked files; `-IncludeMissing` shows stale entries.
- `Start-PwshXdrLiveDashboard -WithLogs` writes timestamped `.log` files under `%LOCALAPPDATA%\PwshXDRSpectre`.
- For alert cache troubleshooting, pair `Alert preload job completed` (with `AlertCount`/`Message`) entries against `Alert cache restore hit/miss` to distinguish empty Graph data from cache/renderer bugs.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `Cannot bind argument to parameter 'X' because it is an empty array/string.` from a live-dashboard call site | Helper missing `[AllowEmptyCollection()]` or `[AllowEmptyString()]` for legitimate empty Graph data. |
| Selected item rendering disappears after navigation | Single shared "current result" variable instead of cache-keyed rebind. |
| Heartbeat advances but keys are ignored | Key polling happens after a `continue` in an auth/loading branch, or RawUI fallback is missing. |
| Alert list does not update after a cache replacement of the same size | Comparison only checked id + count; add a stable id/status/severity/title signature. |
| Action panel labels wrap onto two lines | Verbose label is being rendered. Shorten the *display* label only; keep the underlying action name for policy checks. |
| Tab colors look out of place vs panel borders | Markup hard-coded somewhere other than `Get-XdrLiveOuterTabsHeader`, or active/inactive colors swapped. |