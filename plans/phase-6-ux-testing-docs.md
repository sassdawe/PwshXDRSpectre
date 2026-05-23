# Phase 6 — UX Hardening, Testing, and Docs

**Status**: 🟡 In Progress  
**Depends on**: All prior phases  
**Blocks**: —  
**Last updated**: 2026-05-23 (layout ratios aligned to current implementation)

---

## Goals

1. Expand the TUI layout to dedicated panes for each major workflow area.
2. Add keyboard help, status indicators, and non-blocking feedback for long-running operations.
3. Expand Pester test coverage for schema validation, context interpolation, memory store behavior, and action payload builders.
4. Validate the full analyst workflow end-to-end in a test tenant.
5. Update all documentation to reflect the final architecture, permissions, and usage.

---

## Tasks

### Workstream 1: Dedicated Layout Panes

- [x] **1.1** Design the final layout with the following panes:
  - **Incidents** — incident list with status, severity, assignment
  - **Alerts** — alerts for selected incident
  - **Entities** — extracted users, devices, files from selected incident/alert
  - **Actions** — available triage and containment actions for current selection
  - **Query Catalog** — available hunting queries filtered by current context *(reserved)*
  - **Query Results** — result table for last executed query *(reserved)*
  - **Activity Log** — recent action history and query runs *(reserved)*
  - **Status Bar** — connection status, analyst identity, last operation result *(reserved)*
- [x] **1.2** Restructure layout to maximize list width and improve panel proportions:
  - Left lists column: `left_lists` ratio 2 with incidents and alerts stacked vertically at ratio 1 each
  - Center details column: `center_details` ratio 3 with incident details and alert details stacked vertically at ratio 1 each
  - Action status column: `action_status` ratio 2 for the right-side action panel
- [x] **1.3** Implement tab-style container for incident details + entities:
  - Tab switching via `Tab` key within incident_details panel
  - Alt+E to jump to entities tab, Alt+D to jump to details tab
  - Visual title indicators: "Incident Details" vs "Related Entities"
  - Updated help text to advertise Tab key for switching tabs
- [ ] **1.4** Apply consistent theming (color palette from `Context.Ui.ThemeColor`)
- [ ] ~~**1.5** Ensure all pane content is readable at 120-column terminal width minimum~~

### Workstream 2: Keyboard Navigation and Help

- [x] **2.1** Define a keyboard shortcut map:
  - `F1` — toggle keyboard help overlay
  - `F5` / `r` — refresh current data
  - `Tab` / `Shift+Tab` — cycle between panes
  - `Arrow keys` — navigate within a list
  - `Enter` — select/confirm
  - `Escape` — cancel / go back
  - `q` — quit (with confirmation)
- [x] **2.2** Implement a keyboard help overlay panel that displays the full shortcut map
- [x] **2.3** Show the shortcut map hint in the status bar (e.g., `F1 Help`)
- [x] **2.4** Ensure all confirmation prompts are keyboard-accessible

### Workstream 3: Non-Blocking Feedback

- [ ] **3.1** Show a spinner or progress indicator in the status bar for all operations that take longer than 200ms
- [ ] **3.2** Long-running operations (device isolation, query execution) must not block keyboard input
- [x] **3.3** Show operation result (success or error) in the status bar for at least 3 seconds after completion
- [x] **3.4** Distinguish transient status messages from persistent error states in the status bar

### Workstream 4: Expanded Pester Tests

- [x] Per-function test file layout completed for every script in `Private/` and `Public/`
- [x] Legacy aggregate helper and entry-script test files retired in favor of dedicated test files
- [x] Full suite runs cleanly with dedicated-file scaffolds in place (`67` passed, `9` skipped placeholders)

**Schema validation tests:**

- [ ] **4.1** `Tests/Test-XdrQuerySchema.Tests.ps1` — covers all schema error cases with named failure messages
- [ ] **4.2** `Tests/Test-XdrTriagePolicy.Tests.ps1` — covers all policy validation error cases

**Context interpolation tests:**

- [ ] **4.3** `Tests/Invoke-XdrQueryInterpolation.Tests.ps1` — all placeholder types; injection-unsafe values rejected
- [ ] **4.4** `Tests/Resolve-XdrQueryParameters.Tests.ps1` — all context binding types; missing required bindings return blocked state

**Memory store tests:**

- [ ] **4.5** `Tests/Save-XdrCheckpoint.Tests.ps1` — round-trip save and restore; no secrets in output
- [ ] **4.6** `Tests/Invoke-XdrStoreRetention.Tests.ps1` — retention limits enforced; most recent records kept
- [ ] **4.7** `Tests/Get-XdrCheckpoint.Tests.ps1` — handles missing file, malformed JSON, and version mismatch

**Action payload tests:**

- [ ] **4.8** `Tests/Invoke-XdrUserContainment.Tests.ps1` — payload correctness for all user actions
- [ ] **4.9** `Tests/Invoke-XdrDeviceContainment.Tests.ps1` — payload correctness for all device actions
- [ ] **4.10** `Tests/Invoke-XdrFileContainment.Tests.ps1` — payload correctness for all file actions
- [ ] **4.11** `Tests/Set-XdrIncidentTriage.Tests.ps1` — payload correctness for all incident triage actions
- [ ] **4.12** `Tests/Set-XdrAlertStatus.Tests.ps1` — payload correctness for all alert status updates

**Full test run gate:**

- [x] **4.13** `Invoke-Pester -CI` passes with zero failures before any merge (validated locally; enforced in `.github/workflows/ci-quality-gates.yml`)

### Workstream 5: End-to-End Test Tenant Validation

- [ ] **5.1** Connect to a test tenant and confirm session establishment and analyst identity resolution
- [ ] **5.2** Load incidents and verify incident list panel populates
- [ ] **5.3** Select an incident, navigate to alerts, and verify alert panel populates
- [ ] **5.4** Select an alert, verify entity extraction populates the entities panel
- [ ] **5.5** Execute an incident triage status change and confirm Defender portal reflects the update
- [ ] **5.6** Execute a query from the catalog and verify results render in the results panel
- [ ] **5.7** Pivot from a query result row to an entity and confirm `Context.Selection.Entity` updates
- [ ] **5.8** Perform a containment action on a test device and confirm MDE action log records the event
- [ ] **5.9** Verify `action-history.jsonl` and `checkpoint.json` are written correctly during the session
- [ ] **5.10** Close and reopen — verify context restore loads the last incident
- [ ] **5.11** Inspect all store files — confirm no credentials or tokens are present

**Audit evidence verification:**

- [ ] **5.12** Confirm incident status changes appear in the Defender audit log
- [ ] **5.13** Confirm device isolation actions appear in the MDE machine action history
- [ ] **5.14** Confirm file indicator blocks appear in the Defender indicators list

### Workstream 6: Documentation Update

- [ ] **6.1** Update `README.md` with:
  - New architecture overview (module structure diagram)
  - Updated prerequisites and permissions list
  - Setup instructions for the new module layout
  - Configuration file reference (`config/triage-policy.json`, `config/memory-store-policy.json`)
  - Query catalog folder structure and JSON schema reference
  - Memory store location and cleanup instructions
  - Known limitations and current v1 scope
- [ ] **6.2** Add `CONTRIBUTING.md` with:
  - How to add a new hunting query
  - How to run the Pester test suite
  - How to extend the triage policy
- [ ] **6.3** Add inline comment documentation to all public functions following the self-explanatory code commenting standard
- [ ] **6.4** Verify all existing `README.md` links are still valid after the module restructure
- [x] **6.5** Add release engineering docs for module manifest, CI quality gates, and PowerShell Gallery publish flow

---

## Acceptance Criteria

- [ ] All seven layout panes are present and populate correctly in the live dashboard
- [ ] `F1` displays a keyboard help overlay with all shortcuts
- [ ] Long-running operations show a spinner and do not block keyboard input
- [ ] `Invoke-Pester -CI` passes with zero failures
- [ ] End-to-end validation passes against a test tenant
- [ ] Defender portal audit logs confirm all triage and containment actions
- [ ] `README.md` accurately reflects the final architecture, setup, and usage

---

## Manual Validation Checklist

- [ ] Full incident → alert → entity → hunt → action flow completes without errors
- [ ] Keyboard help overlay opens and closes with `F1`
- [ ] Query execution shows spinner while running; results appear after completion
- [ ] Confirmation prompts appear for all disruptive actions
- [ ] Context restore works after closing and reopening the TUI
- [ ] `README.md` setup instructions successfully guide a fresh install to a running dashboard

---

## Relevant Files

- [README.md](../README.md) — primary documentation target
- [PwshXDRSpectre.psm1](../PwshXDRSpectre.psm1) — module entry point
- [Public/Start-PwshXdrLiveDashboard.ps1](../Public/Start-PwshXdrLiveDashboard.ps1) — layout entry point
- [Tests/](../Tests/) — Pester test suite root
