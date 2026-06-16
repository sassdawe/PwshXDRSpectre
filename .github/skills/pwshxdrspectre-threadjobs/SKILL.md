---
name: pwshxdrspectre-threadjobs
description: 'Background ThreadJob patterns for the PwshXDRSpectre live dashboard: launching Microsoft Graph and KQL hunting work without stalling the TUI render loop, projecting lean view models out of jobs, folding Receive-Job results into UI state from the main loop, debouncing and deduplicating per-incident/per-query jobs, and avoiding argument-list pitfalls. Use when adding or modifying any Start-ThreadJob call, alert/incident/entity preload work, hunting query execution, or any code under Invoke-XdrLive*JobProcessing. Covers comma-after-scriptblock bugs, returning Graph SDK objects vs view models, and main-loop polling discipline.'
---

# PwshXDRSpectre ThreadJob Execution

Repo-specific rules for `ThreadJob` (Microsoft.PowerShell.ThreadJob) usage. Generic PowerShell job docs are not repeated.

## When to Use This Skill

- Adding or modifying any `Start-ThreadJob` call
- Editing `Invoke-XdrLiveAlertLoadJobProcessing.ps1`, `Invoke-XdrLiveQueryJobProcessing.ps1`, or any future `Invoke-XdrLive*JobProcessing` helper
- Wiring a new background data source (entity enrichment, hunting query, Graph expand) into the dashboard
- Diagnosing a stalled heartbeat, missing job result, or duplicated job

## Why ThreadJob (Not `Start-Job`)

Process jobs (`Start-Job`) serialize parameters, which loses Graph SDK object identity and is far slower. `ThreadJob` shares the AppDomain, so we can pass typed objects in and read typed objects back. The dashboard assumes thread-job semantics throughout.

## Launch Pattern

```powershell
$job = Start-ThreadJob -ScriptBlock {
    param($IncidentId, $GraphContext)
    # Do Graph work; return a LEAN view model, not the SDK object.
    $incident = Get-MgSecurityIncident -IncidentId $IncidentId -ExpandProperty 'alerts'
    [pscustomobject]@{
        IncidentId = $IncidentId
        Alerts     = @($incident.Alerts | ForEach-Object {
            [pscustomobject]@{
                Id       = $_.Id
                Title    = $_.Title
                Status   = $_.Status
                Severity = $_.Severity
                # Evidence/Entities only if needed downstream
            }
        })
    }
} -ArgumentList $incidentId $graphContext   # NOTE: spaces, no commas after }
```

### Argument-list gotcha

Do **not** put commas after the closing `}` of the script block when listing arguments. PowerShell flattens commas into a single array argument and downstream `param(...)` bindings receive `$null` or malformed values. This has previously corrupted log paths in this repo.

- BAD: `Start-ThreadJob -ScriptBlock { ... }, $a, $b`
- GOOD: `Start-ThreadJob -ScriptBlock { ... } -ArgumentList $a $b`
- GOOD: pass a single payload `[pscustomobject]@{...}` and destructure inside `param(...)`

## Return Lean View Models

Never return raw `Microsoft.Graph.*` SDK objects from a thread job. They carry deep object graphs that stall `Receive-Job` and rendering. Project the minimal fields needed by the UI (id, title, status, severity, plus any specific Evidence/Entities the dashboard renders).

If a downstream helper still wants "the incident", build a `[pscustomobject]` shaped like the relevant Graph fields rather than handing through the SDK type.

## Folding Results Back

All result handling happens in the **main render loop**, not inside the job. Each tick:

1. Iterate the per-feature job dictionary (`$AlertLoadJobsByIncidentId`, query job map, etc.).
2. For each completed job: `Receive-Job -Job $job -Keep:$false`, then `Remove-Job $job`.
3. Update the corresponding cache (`$AlertsByIncidentId[$id] = $result.Alerts`).
4. If the result corresponds to the currently selected item, rebind the visible UI from the cache.
5. Log a single `Alert preload job completed` / `Query job completed` line with `IncidentId` / `QueryId`, count, and any error message.

This keeps render and input handling on the main thread; jobs only produce data.

## Deduplication & Debounce

- Key in-flight jobs by their natural id (incident id, query id) in a hashtable. **Skip launching** if a job for that id is already running.
- For preload queues (alert preloads), dequeue + check cache + check in-flight before starting a new job.
- After completion, remove the key from the in-flight map *before* updating the cache, so a follow-up navigation can re-trigger if needed.

## Main-Loop Discipline (Job Side)

- The render loop's throttle and key polling must not be skipped while job processing runs. Process at most a bounded number of completed jobs per tick if many complete simultaneously; the rest will be picked up next tick.
- Avoid fan-out: do not start N jobs at once for entity enrichment of every visible incident. Even thread jobs starve the TUI when several `Receive-Job` completions arrive together.
- Lazy is the default. Alert/entity loading must be explicit (Enter, Alt+L, Alt+Shift+L). Tab switching and arrow navigation must not start Graph jobs.

## Hunting Query Specifics

- All KQL execution goes through a thread job; never call the query API on the main thread.
- Cache results by `Get-XdrQueryResultCacheKey` (query id + resolved parameter snapshot). Switching incidents/entities must produce a different cache key, otherwise the previous incident's result will be reused.
- Job result schema validation lives in `Test-XdrQuerySchema`; run results through it before caching.

## Logging

- Every job launch logs a `… job started` line with the natural id and parameter snapshot.
- Every completion logs `Alert preload job completed` / `Query job completed` with `AlertCount` / `RowCount` and `Message` (empty string on success).
- For alert cache troubleshooting, pair completion lines against `Alert cache restore hit/miss` to distinguish "Graph returned no data" from "cache/renderer drift".

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Heartbeat stops while a job runs | Job processing on the main thread, or `Receive-Job` returning a full Graph SDK object. Switch to a lean view model. |
| `Cannot bind argument to parameter 'X'` from a job result helper | Job returned `@()` / `''`; helper needs `[AllowEmptyCollection()]` / `[AllowEmptyString()]`. |
| Two jobs running for the same incident/query | Missing in-flight dedup check before `Start-ThreadJob`. |
| Result arrives but UI does not update | Cache updated but currently selected item not rebound from cache after completion. |
| Argument values inside the job are `$null` or shifted | Comma after `}` in `Start-ThreadJob -ScriptBlock { … }, $a, $b`. Use `-ArgumentList $a $b`. |
| Same-key cache replaces the visible alert list with stale data | Comparison used id + count only; switch to a stable id/status/severity/title signature. |