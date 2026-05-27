# Defender XDR Analyst TUI — Plan Index

Build a modular PowerShell terminal app on PSSpectreConsole that supports full analyst workflows: incident/alert triage, user/device/file containment, context-aware KQL hunting from JSON files, and persistent workflow memory for agent-style operations.

**API approach**: Microsoft Graph cmdlets + direct Graph REST when cmdlets are insufficient  
**Tenant model**: Single active tenant for v1  
**Hunting queries**: Repository folder as JSON  
**Memory store**: Persists checkpoints, entity context, action history, and query-run metadata  
**Backwards compatibility**: Not required — internal tool in active development

---

## Phase Status

| Phase | Title | Status | Depends on |
| ----- | ----- | ------ | ---------- |
| [Phase 1](phase-1-foundation.md) | Foundation and Architecture | 🟡 In Progress | — |
| [Phase 2](phase-2-incident-alert-ops.md) | Incident and Alert Operations | 🟡 In Progress (implementation complete; manual validation pending) | Phase 1 |
| [Phase 3](phase-3-entity-containment.md) | Entity Pivots and Containment | 🟡 In Progress | Phase 2 |
| [Phase 4](phase-4-hunting-query.md) | Hunting Query Engine | 🟡 In Progress | Phase 1 |
| [Phase 5](phase-5-workflow-memory.md) | Agent Workflow Memory Store | ⚪ Not Started | Phase 1, Phase 3, Phase 4 |
| [Phase 6](phase-6-outer-panel-tabs.md) | Outer Panel Tabs and Placeholder Workflows | 🟡 In Progress | Phase 1, Phase 2, Phase 4 |
| [Phase 7](phase-7-ux-testing-docs.md) | UX Hardening, Testing, and Docs | 🟡 In Progress | All prior phases, Phase 6 |

**Status key**: ⚪ Not Started · 🟡 In Progress · 🔴 Blocked · ✅ Completed

---

## Overall Progress

### Phase 1 — Foundation and Architecture

- [x] Runtime context model (`New-XdrRuntimeContext`)
- [x] Module and function layout refactor
- [x] Service layer and data contracts
- [x] Operation result and error contract
- [x] Entry-point consolidation
- [x] Testing baseline (Pester)

### Phase 2 — Incident and Alert Operations

- [x] Policy file schema and loader (`config/triage-policy.json`)
- [x] Incident triage service (`Set-XdrIncidentTriage`)
- [x] Alert triage service (`Set-XdrAlertStatus`)
- [x] Assign-to-me identity resolver
- [x] Confirmation safety policy enforcement
- [x] Dedicated disabled-reasons panel
- [x] Resolution workflow UX hardening (`Alt+` shortcuts, `Ctrl+Q`, `PgUp/PgDn`, focus lock)
- [x] Permission-aware degraded mode and visual indicators (capability downgrade + red logo)
- [x] Active panel border theme highlighting
- [x] Connect-session permission classification tests
- [x] Phase 2 planned and extracted-helper test items complete (63/63 passing)

### Phase 3 — Entity Pivots and Containment

- [~] Entity extraction and normalization
- [ ] User containment (revoke sessions, disable account)
- [ ] Device containment (isolate, remediation)
- [ ] File containment (quarantine, block indicator)
- [~] Runtime action history (redaction-ready, Phase 5-compatible)

### Phase 4 — Hunting Query Engine

- [x] Query catalog JSON schema and folder
- [x] Startup loader and schema validation
- [x] Context binding for KQL parameter injection
- [~] TUI flow (select, preview, execute, navigate results)
- [x] Query run metadata recording
- [x] Async hunting query execution and context-aware result caching

### Phase 5 — Agent Workflow Memory Store

- [ ] Local JSON persistence layer
- [ ] Append-only history with retention rules
- [ ] Per-user encryption for sensitive persisted history/query records
- [ ] Store APIs (checkpoint, history, query run, cleanup)
- [ ] Startup context restore

### Phase 6 — Outer Panel Tabs and Placeholder Workflows

- [x] Outer dashboard frame with tab strip in the frame header
- [x] Neutral physical layout slots separated from workflow-specific logical panel names
- [x] Incidents and Hunting rendered as top-level tab workflows
- [x] Placeholder tabs for Welcome, Query Library, Quarantine, Action Center, Settings, and Help
- [ ] Placeholder tab graduation paths and tests
- [ ] Manual validation for tab switching while background jobs are active

### Phase 7 — UX Hardening, Testing, and Docs

- [ ] Dedicated layout panes (Incidents, Alerts, Entities, Actions, Query Catalog, Results, Log)
- [~] Keyboard help and non-blocking feedback (F1 overlay, q/Ctrl+Q quit confirmation, r refresh alias, transient/persistent status behavior, non-blocking hunting query execution)
- [~] Pester test expansion
- [x] Dedicated `Tests/<Function>.Tests.ps1` coverage layout for every `Private/` and `Public/` script
- [ ] End-to-end test tenant validation
- [ ] Documentation update

---

## Decisions Captured

| Decision | Choice |
| -------- | ------ |
| API approach | Microsoft Graph cmdlets + direct REST |
| Tenant model | Single active tenant (v1) |
| Query storage | Repository JSON folder |
| Memory store | Local JSON, append-only |
| v1 scope | Incident triage, alert triage, user/device/file containment |
| Backwards compatibility | Not required |
