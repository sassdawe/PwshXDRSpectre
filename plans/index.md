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
|-------|-------|--------|------------|
| [Phase 1](phase-1-foundation.md) | Foundation and Architecture | 🟡 In Progress | — |
| [Phase 2](phase-2-incident-alert-ops.md) | Incident and Alert Operations | ⚪ Not Started | Phase 1 |
| [Phase 3](phase-3-entity-containment.md) | Entity Pivots and Containment | ⚪ Not Started | Phase 2 |
| [Phase 4](phase-4-hunting-query.md) | Hunting Query Engine | ⚪ Not Started | Phase 1 |
| [Phase 5](phase-5-workflow-memory.md) | Agent Workflow Memory Store | ⚪ Not Started | Phase 1, Phase 4 |
| [Phase 6](phase-6-ux-testing-docs.md) | UX Hardening, Testing, and Docs | ⚪ Not Started | All phases |

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
- [ ] Policy file schema and loader (`config/triage-policy.json`)
- [ ] Incident triage service (`Set-XdrIncidentTriage`)
- [ ] Alert triage service (`Set-XdrAlertStatus`)
- [ ] Assign-to-me identity resolver
- [ ] Confirmation safety policy enforcement
- [ ] Dedicated disabled-reasons panel

### Phase 3 — Entity Pivots and Containment
- [ ] Entity extraction and normalization
- [ ] User containment (revoke sessions, disable account)
- [ ] Device containment (isolate, remediation)
- [ ] File containment (quarantine, block indicator)
- [ ] Action history persistence

### Phase 4 — Hunting Query Engine
- [ ] Query catalog JSON schema and folder
- [ ] Startup loader and schema validation
- [ ] Context binding for KQL parameter injection
- [ ] TUI flow (select, preview, execute, navigate results)
- [ ] Query run metadata recording

### Phase 5 — Agent Workflow Memory Store
- [ ] Local JSON persistence layer
- [ ] Append-only history with retention rules
- [ ] Store APIs (checkpoint, history, query run, cleanup)
- [ ] Startup context restore

### Phase 6 — UX Hardening, Testing, and Docs
- [ ] Dedicated layout panes (Incidents, Alerts, Entities, Actions, Query Catalog, Results, Log)
- [ ] Keyboard help and non-blocking feedback
- [ ] Pester test expansion
- [ ] End-to-end test tenant validation
- [ ] Documentation update

---

## Decisions Captured

| Decision | Choice |
|----------|--------|
| API approach | Microsoft Graph cmdlets + direct REST |
| Tenant model | Single active tenant (v1) |
| Query storage | Repository JSON folder |
| Memory store | Local JSON, append-only |
| v1 scope | Incident triage, alert triage, user/device/file containment |
| Backwards compatibility | Not required |
