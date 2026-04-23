# Phase 5 — Agent Workflow Memory Store

**Status**: ⚪ Not Started  
**Depends on**: [Phase 1 — Foundation](phase-1-foundation.md), [Phase 4 — Hunting Query Engine](phase-4-hunting-query.md)  
**Blocks**: —  
**Last updated**: 2026-04-21

---

## Goals

1. Implement local JSON persistence for analyst checkpoints, context snapshots, action history, and query run records.
2. Use an append-only history model with versioning and configurable retention rules.
3. Provide clean store APIs for checkpoint save/load, history append, query run append, and retention cleanup.
4. Restore the last analyst context on startup so sessions resume where they left off.

---

## Tasks

### Workstream 1: Store Layout and Schema

- [ ] **1.1** Define the memory store directory — default to `~/.pwshxdr/` (configurable via `Context.Ui`)
- [ ] **1.2** Define the store file layout:
  - `~/.pwshxdr/checkpoint.json` — latest context snapshot (overwritten on each checkpoint save)
  - `~/.pwshxdr/action-history.jsonl` — append-only log of executed actions (one JSON object per line)
  - `~/.pwshxdr/query-runs.jsonl` — append-only log of query run records (one JSON object per line)
  - `~/.pwshxdr/session-log.jsonl` — session start/end events (one JSON object per line)
- [ ] **1.3** Define the checkpoint schema:
  - `Version` — schema version string (e.g., `1.0`)
  - `SavedAt` — ISO 8601 timestamp
  - `TenantId`
  - `Analyst` — display name and identity
  - `SelectedIncidentId`
  - `SelectedAlertId`
  - `SelectedEntityId`
  - `RecentActionIds` — last 10 action IDs
  - `RecentQueryRunIds` — last 10 query run IDs
- [ ] **1.4** Ensure no secrets, tokens, or credentials are written to any store file

### Workstream 2: Store API Implementation

- [ ] **2.1** Implement `Private/Save-XdrCheckpoint.ps1` — serializes current context to `checkpoint.json`
- [ ] **2.2** Implement `Private/Get-XdrCheckpoint.ps1` — reads and deserializes `checkpoint.json`; returns `$null` if file does not exist or is unreadable
- [ ] **2.3** Implement `Private/Add-XdrActionHistoryRecord.ps1` — appends an action record to `action-history.jsonl`
- [ ] **2.4** Implement `Private/Add-XdrQueryRunRecord.ps1` — appends a query run record to `query-runs.jsonl`
- [ ] **2.5** Implement `Private/Write-XdrSessionEvent.ps1` — appends a session start or end event to `session-log.jsonl`
- [ ] **2.6** All store writes use `ConvertTo-Json -Compress` and append with UTF-8 encoding — never overwrite append-only files
- [ ] **2.7** All store reads handle missing files and malformed JSON gracefully (return empty/null, log warning to diagnostics)

### Workstream 3: Retention and Cleanup

- [ ] **3.1** Define retention configuration in `config/memory-store-policy.json`:
  - `ActionHistoryMaxRecords` — maximum number of action history lines to retain (default: 500)
  - `QueryRunMaxRecords` — maximum number of query run lines to retain (default: 200)
  - `SessionLogRetentionDays` — number of days to keep session events (default: 30)
- [ ] **3.2** Implement `Private/Invoke-XdrStoreRetention.ps1` — reads the policy and trims each append-only file to its configured limit
- [ ] **3.3** Retention strategy: keep the most recent N records; discard oldest
- [ ] **3.4** Call `Invoke-XdrStoreRetention` on session start after context restore completes

### Workstream 4: Startup Context Restore

- [ ] **4.1** On startup, call `Get-XdrCheckpoint` to retrieve the last saved context
- [ ] **4.2** If a valid checkpoint exists:
  - Pre-populate `Context.Session.TenantId` from checkpoint (overrideable by explicit parameter)
  - Restore `Context.Selection.Incident` by fetching the incident by ID (if still accessible)
  - Show a status message confirming the restored context and last save timestamp
- [ ] **4.3** If no checkpoint exists or restore fails, proceed with fresh context and log a diagnostic message (non-terminating)
- [ ] **4.4** Expose `Clear-XdrWorkflowMemory` as a public function to let analysts wipe all persisted store files
- [ ] **4.5** Add confirmation gate before `Clear-XdrWorkflowMemory` executes

### Workstream 5: Automatic Checkpoint Triggers

- [ ] **5.1** Save a checkpoint automatically after each of the following events:
  - Successful incident selection
  - Successful alert selection
  - Successful entity selection
  - Successful triage action (status change, classification, etc.)
  - Successful containment action
  - Successful query execution
- [ ] **5.2** Use debounce logic — do not save more than once per 5 seconds regardless of event frequency
- [ ] **5.3** Store write errors must not terminate or crash the TUI — log to `Context.Diagnostics.Warnings`

### Workstream 6: Tests

- [ ] **6.1** `Tests/Save-XdrCheckpoint.Tests.ps1` — writes expected JSON structure; does not include secrets
- [ ] **6.2** `Tests/Get-XdrCheckpoint.Tests.ps1` — returns deserialized object from valid file; returns `$null` for missing file; returns `$null` for malformed JSON
- [ ] **6.3** `Tests/Add-XdrActionHistoryRecord.Tests.ps1` — appends without overwriting; record is valid JSON line
- [ ] **6.4** `Tests/Add-XdrQueryRunRecord.Tests.ps1` — appends without overwriting; record is valid JSON line
- [ ] **6.5** `Tests/Invoke-XdrStoreRetention.Tests.ps1` — trims files to configured limits; retains most recent records
- [ ] **6.6** `Tests/Clear-XdrWorkflowMemory.Tests.ps1` — removes all store files after confirmation; does nothing without confirmation
- [ ] **6.7** Verify no test writes to production store path — mock or redirect store directory in all tests

---

## Acceptance Criteria

- [ ] `checkpoint.json` is written after each qualifying event and can be restored on the next startup
- [ ] `action-history.jsonl` and `query-runs.jsonl` are append-only — previous records are never modified or deleted by normal operation
- [ ] Retention cleanup runs on startup and trims files to configured limits
- [ ] No secrets, tokens, or credentials appear in any store file
- [ ] Store read/write errors are non-terminating — they surface in diagnostics only
- [ ] `Clear-XdrWorkflowMemory` requires confirmation before deleting store files

---

## Manual Validation Checklist

- [ ] Start a session, select an incident — verify `checkpoint.json` is written
- [ ] Close and reopen the TUI — verify the selected incident is restored
- [ ] Execute a triage action — verify the action appears in `action-history.jsonl`
- [ ] Run a hunting query — verify the run appears in `query-runs.jsonl`
- [ ] Run `Invoke-XdrStoreRetention` manually — verify old records are trimmed
- [ ] Call `Clear-XdrWorkflowMemory` — verify confirmation prompt appears; verify files are removed after confirmation
- [ ] Inspect `checkpoint.json` — verify no tokens or passwords are present
- [ ] Deliberately corrupt `checkpoint.json` — verify startup proceeds with fresh context and logs a warning

---

## Security Notes

- The store directory (`~/.pwshxdr/`) is user-scoped — no shared access across analyst accounts.
- Access tokens, client secrets, and passwords must never be written to the store.
- `Save-XdrCheckpoint` must explicitly exclude `Context.Session.AccessToken` and any credential fields.
- Validate store file paths are within the expected store directory before any read or write to prevent path traversal.

---

## New Functions

| Function | Visibility | Purpose |
|----------|------------|---------|
| `Save-XdrCheckpoint` | Private | Serializes current context snapshot to `checkpoint.json` |
| `Get-XdrCheckpoint` | Private | Reads and deserializes the last saved checkpoint |
| `Add-XdrActionHistoryRecord` | Private | Appends an action record to `action-history.jsonl` |
| `Add-XdrQueryRunRecord` | Private | Appends a query run record to `query-runs.jsonl` |
| `Write-XdrSessionEvent` | Private | Appends a session start/end event to `session-log.jsonl` |
| `Invoke-XdrStoreRetention` | Private | Trims append-only files to configured retention limits |
| `Clear-XdrWorkflowMemory` | Public | Removes all store files after analyst confirmation |
