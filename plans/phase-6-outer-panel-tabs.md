# Phase 6 — Outer Panel Tabs and Placeholder Workflows

**Status**: 🟡 In Progress
**Depends on**: Phase 1, Phase 2, Phase 4
**Blocks**: Phase 7 UX hardening, testing, and docs
**Last updated**: 2026-05-27

## Goals

1. Make the outer dashboard frame and top tab strip the primary navigation shell.
2. Separate physical panel slots from logical workflow panel names so each tab can use the same screen real estate without overloading incident-specific names.
3. Keep the Incidents and Hunting workflows fully usable inside the tabbed shell.
4. Provide clear placeholder behavior for future top-level tabs without blocking the live loop, background jobs, or help/status refresh.
5. Document how placeholder tabs should graduate into full workflow tabs over time.

## Design Summary

The dashboard uses one outer `dashboard_frame` panel. Its header contains the top-level tab strip, and its body contains a stable physical layout. The layout slots describe screen position only:

| Slot ID | Role |
| --- | --- |
| `left_top` | Primary list for the active workflow. |
| `left_bottom` | Secondary list, alert list, or activity stream. |
| `center_top` | Details, preview, or entity list. |
| `center_bottom` | Selected item details or workflow results. |
| `right_actions` | Actions, disabled-state reasons, status, or modal workflows. |
| `help` | Context-aware help, live status, heartbeat, and diagnostics. |

Logical panel names describe workflow meaning. `Resolve-XdrLivePanelSlot` maps logical panels onto physical slots. `Get-XdrLivePanelOrder` defines which logical panels can receive keyboard focus for the active workflow.

## Current Top-Level Tabs

| Tab | Shortcut | Current state | Future plan |
| --- | --- | --- | --- |
| Welcome | `Alt+1` | Placeholder orientation and session overview. | Add session summary, tenant health, recent work, and quick-start actions. |
| Incidents | `Alt+2` | Full workflow for incident list, incident details, alert list, alert details, and actions. | Continue hardening alert/entity loading, triage actions, and selection persistence. |
| Hunting | `Alt+3` or `Alt+H` | Full workflow for query catalog, preview, activity, results, and query actions. | Add query library management, result pivoting, and saved run review. |
| Query Library | `Alt+4` | Placeholder panels for query metadata, versions, preview, and actions. | Promote to saved query authoring, validation, version history, and import/export. |
| Quarantine | `Alt+5` | Placeholder panels marked under construction. | Promote to quarantine item review, release/delete decisions, and evidence trail. |
| Action Center | `Alt+6` | Placeholder panels marked under construction. | Promote to pending action review, approval, retry, and rollback workflows. |
| Settings | `Alt+7` | Placeholder diagnostics/settings panels. | Promote to runtime settings, theme, log viewer, permission state, and feature toggles. |
| Help | `Alt+8` | Placeholder help topics and tips. | Promote to complete keyboard reference, troubleshooting, and workflow guide. |

## Implemented Behavior

- The tab strip is rendered as the `dashboard_frame` header instead of a separate layout row.
- Physical layout slots are neutral and stable across tabs.
- Incidents and Hunting use their own logical panel names.
- Placeholder tabs render tab-specific logical panel names so future workflows do not inherit incident-specific focus or help text.
- Top-level tab activation resets focus order through `Set-XdrLiveActiveTab`.
- `Alt+H` toggles between the Incidents and Hunting workflows.
- The help panel continues to refresh while placeholder tabs are selected.
- Incident, alert, entity, and query background jobs continue to be processed while placeholder tabs are selected.

## Placeholder Tab Graduation Rules

When turning a placeholder tab into a full workflow tab:

1. Add or update logical panel names for that workflow.
2. Map the logical panels to physical slots in `Resolve-XdrLivePanelSlot`.
3. Add the focus order in `Get-XdrLivePanelOrder`.
4. Add context-aware shortcuts in `Get-ContextAwareHelpLines`.
5. Add friendly panel labels in `Get-XdrLiveHelpPanelContent`.
6. Render workflow-specific content in the dashboard or an extracted renderer helper.
7. Add Pester coverage for routing, focus order, help text, and placeholder removal.
8. Update `docs/tabs-and-panels.md` with the new workflow behavior.

If a placeholder or workflow behavior is temporarily disabled for debugging, document what was disabled, why it was disabled, and the exact function or condition to restore before merging the change.

## Tasks

### Workstream 1: Outer Frame and Tab Navigation

- [x] **1.1** Render a single outer `dashboard_frame` around the dashboard.
- [x] **1.2** Move the top-level tab strip into the outer frame header.
- [x] **1.3** Preserve vertical space by removing the separate tab/header row.
- [x] **1.4** Add top-level tab activation through keyboard shortcuts.
- [x] **1.5** Keep tab switching independent from background job processing.

### Workstream 2: Logical Panel Identity

- [x] **2.1** Rename physical screen positions to neutral slot IDs.
- [x] **2.2** Introduce workflow-specific logical panel IDs for Incidents.
- [x] **2.3** Introduce workflow-specific logical panel IDs for Hunting.
- [x] **2.4** Add placeholder logical panel IDs for non-workflow tabs.
- [x] **2.5** Route panel border, header, help, and focus behavior through logical panel names.

### Workstream 3: Incidents and Hunting Workflow Fit

- [x] **3.1** Keep incident list, incident details, alert list, alert details, and actions inside the new shell.
- [x] **3.2** Move Hunting into the top-level Hunting tab instead of a hidden Incident-tab mode.
- [x] **3.3** Keep Hunting query execution off the live UI loop.
- [x] **3.4** Preserve selected incident/entity context when entering Hunting.
- [ ] **3.5** Add manual validation notes for switching between Incidents and Hunting while jobs are active.

### Workstream 4: Placeholder Tab Roadmap

- [x] **4.1** Render placeholders for Welcome, Query Library, Quarantine, Action Center, Settings, and Help.
- [x] **4.2** Give placeholders tab-specific logical panel names.
- [ ] **4.3** Add lightweight actions for placeholder tabs where useful, such as returning to Incidents or opening logs.
- [ ] **4.4** Define the first full workflow to graduate from placeholder status.
- [ ] **4.5** Add acceptance tests for placeholder tab rendering and focus reset.

### Workstream 5: Documentation and Debugging Notes

- [x] **5.1** Document physical slots, logical panels, and tab behavior in `docs/tabs-and-panels.md`.
- [x] **5.2** Document alert loading and cache diagnostics after the alert cache debugging session.
- [ ] **5.3** Add a short troubleshooting section for tab/focus bugs.
- [ ] **5.4** Keep a restore note whenever workflow behavior is disabled for debugging.

## Acceptance Criteria

- [x] The dashboard renders inside one outer frame with the tab strip as the frame title.
- [x] Physical slot names do not encode workflow semantics.
- [x] Incidents and Hunting have distinct logical panel names and focus order.
- [x] Placeholder tabs render stable placeholder content without breaking the live loop.
- [x] Help and status diagnostics reflect the active tab and logical focus panel.
- [ ] Placeholder tabs have documented graduation paths and tests for future workflow promotion.
- [ ] Manual validation confirms tab switching does not interrupt active background jobs.

## Relevant Files

- [docs/tabs-and-panels.md](../docs/tabs-and-panels.md) — user-facing tab and panel behavior.
- [src/Public/Start-PwshXdrLiveDashboard.ps1](../src/Public/Start-PwshXdrLiveDashboard.ps1) — live dashboard shell and render loop.
- [src/Private/Resolve-XdrLivePanelSlot.ps1](../src/Private/Resolve-XdrLivePanelSlot.ps1) — logical panel to physical slot mapping.
- [src/Private/Get-XdrLivePanelOrder.ps1](../src/Private/Get-XdrLivePanelOrder.ps1) — tab-specific focus order.
- [src/Private/Set-XdrLiveActiveTab.ps1](../src/Private/Set-XdrLiveActiveTab.ps1) — tab activation and focus reset.
- [src/Private/Show-XdrLiveNonIncidentTab.ps1](../src/Private/Show-XdrLiveNonIncidentTab.ps1) — placeholder tab renderer.
