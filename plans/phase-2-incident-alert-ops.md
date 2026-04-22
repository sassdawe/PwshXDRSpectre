# Phase 2 — Incident and Alert Operations

**Status**: 🟡 In Progress (implementation complete; remaining manual validation only)  
**Depends on**: [Phase 1 — Foundation](phase-1-foundation.md)  
**Blocks**: Phase 3  
**Last updated**: 2026-04-22

---

## Goals

1. Implement complete incident triage actions: assign/unassign, status, classification, determination, and comments.
2. Implement alert triage actions with drill-down details and status updates.
3. Add confirmations for impactful actions with clear rollback/result messaging.
4. Add permission checks with graceful degraded behavior when required delegated permissions are missing.

## Scope Lock

### Incident triage

- Supported status transitions: `Active`, `In progress`, `Resolved`
- Graph enum values: `active`, `inProgress`, `resolved`
- Initial classification options: `Unclassified`, `True positive / Malware`, `False positive / Not malicious`
- Classification and determination must be extendable via configuration file
- If incident is resolved without a comment, auto-fill: `Resolved using PwshXDRSpectre`
- Assign-to-me identity fallback order: `mail` → `userPrincipalName`

### Alert triage

- Supported status transitions: `New`, `In progress`, `Resolved`
- Graph enum values: `new`, `inProgress`, `resolved`

### UX and safety

- Disabled/unsupported action reasons must always be visible in a dedicated panel
- Potentially disruptive actions must be confirmation-gated via a policy table
- Confirmation policy must be extendable in configuration and validated by tests

---

## Tasks

### Workstream 1: Policy File and Configuration

- [x] **1.1** Create `config/triage-policy.json` with the following minimum sections:
  - `incidentStatusMap` — display label to Graph enum value
  - `alertStatusMap` — display label to Graph enum value
  - `classifications` — list of available classification options
  - `determinations` — list of available determination options
  - `defaultResolvingComment` — auto-fill text for resolved incidents without comments
  - `safetyPolicy` — action confirmation requirements table
- [x] **1.2** Implement `Private/Get-XdrTriagePolicy.ps1` — loads and returns the parsed policy from `config/triage-policy.json`
- [x] **1.3** Implement `Private/Test-XdrTriageValue.ps1` — validates that a given display value exists in the policy map
- [x] **1.4** Implement `Private/Resolve-XdrGraphEnumValue.ps1` — translates a display label to its Graph enum value using the policy map
- [x] **1.5** Implement policy schema validation with the following rules:
  - Required keys must exist
  - No duplicate display labels within a map
  - No duplicate Graph enum values within a map
  - All safety policy levels must be valid
  - Unknown actions in safety policy fail validation
  - Status and classification entries match allowed schema

### Workstream 2: Incident Triage Service

- [x] **2.1** Implement `Public/Set-XdrIncidentTriage.ps1` with support for:
  - Status (`active`, `inProgress`, `resolved`)
  - Classification
  - Determination
  - AssignedTo
  - Comment
- [x] **2.2** Implement `Private/Get-XdrAssignTargetIdentity.ps1` — resolves analyst identity using `mail` first, then `userPrincipalName` as fallback
- [x] **2.3** Ensure resolving-comment auto-fill triggers only when comment is missing and status is `resolved`
- [x] **2.4** Ensure service builds proper Graph PATCH payload before calling `Invoke-XdrOperation`
- [x] **2.5** Implement `Public/Get-XdrTriageOptions.ps1` — returns available status, classification, and determination options from policy
- [x] **2.6** Route resolving comments to Graph incident `resolvingComment` property when closing incidents
- [x] **2.7** Route normal incident comments through `POST /security/incidents/{incidentId}/comments`
- [x] **2.8** Ensure selected incident objects missing `ResolvingComment` are updated safely without runtime failure

### Workstream 3: Alert Triage Service

- [x] **3.1** Implement `Public/Set-XdrAlertStatus.ps1` with support for `new`, `inProgress`, `resolved`
- [x] **3.2** Ensure service builds proper Graph PATCH payload before calling `Invoke-XdrOperation`
- [x] **3.3** Validate the requested status exists in `alertStatusMap` before executing

### Workstream 4: Action Safety Policy

- [x] **4.1** Implement `Private/Get-XdrActionSafetyPolicy.ps1` — returns the safety policy for a given action name
- [x] **4.2** Implement `Private/Test-XdrActionSafetyPolicy.ps1` — returns whether an action requires confirmation
- [x] **4.3** Implement `Private/Get-XdrActionDisableReasons.ps1` — returns a list of reasons why an action is unavailable, given current context and capabilities
- [x] **4.4** Wire confirmation prompts for all actions flagged as `confirm: true` in the policy

**Default safety policy table** (editable in `config/triage-policy.json`):

| Action | Confirmation required | Prompt wording |
|--------|-----------------------|----------------|
| Assign incident to me | No | — |
| Clear incident assignment | Yes | Clear assignment from this incident? |
| Set incident status to Active | No | — |
| Set incident status to In progress | No | — |
| Set incident status to Resolved | Yes | Resolve this incident now? |
| Set incident classification | No | — |
| Set incident determination | No | — |
| Auto-fill resolving comment | No | — |
| Set alert status to New | Yes | Reopen this alert as New? |
| Set alert status to In progress | No | — |
| Set alert status to Resolved | Yes | Resolve this alert now? |

### Workstream 5: Disabled-Reasons Panel

- [x] **5.1** Add a dedicated UI panel that always shows action availability and reason text
- [x] **5.2** Populate reason text from these sources:
  - Missing capability
  - Missing selection context (no incident/alert selected)
  - Invalid transition for current status
  - Policy disabled
- [x] **5.3** Panel updates whenever selected incident, alert, or action changes
- [ ] **5.4** Panel visually distinguishes `Blocked` from `Warning` states

### Workstream 6: Dashboard Wiring

- [x] **6.1** Wire live dashboard (`Start-PwshXdrLiveDashboard`) to all triage services
- [x] **6.2** Confirm no live dashboard file calls Graph cmdlets directly for any triage operation
- [x] **6.3** Confirm disabled-reasons panel is rendered in live dashboard

### Workstream 7: Tests

**Unit tests:**

- [x] **7.1** `Tests/Get-XdrTriagePolicy.Tests.ps1` — policy loader parses valid config
- [x] **7.2** Policy validator rejects typos and unknown values
- [x] **7.3** Incident status display-to-Graph mapping works for all three statuses
- [x] **7.4** Alert status display-to-Graph mapping works for all three statuses
- [x] **7.5** Classification and determination mapping resolves initial options
- [x] **7.6** Missing resolving comment on resolved incident auto-fills default text
- [x] **7.7** Assign target resolver uses `mail` first and `userPrincipalName` as fallback
- [x] **7.8** Safety policy correctly flags confirm-required actions
- [x] **7.9** Disabled reason generator returns deterministic reasons

**Mocked service tests:**

- [x] **7.10** Incident triage service builds proper payload for each status
- [x] **7.11** Incident resolve flow includes default comment when field is empty
- [x] **7.12** Alert triage service builds proper payload for each status
- [x] **7.13** Capability failure returns structured non-terminating error
- [x] **7.14** Invalid policy values fail closed before any Graph call is made
- [x] **7.17** Normal incident comment flow posts to incident comments endpoint
- [x] **7.18** Resolving comment update is safe when selected incident initially lacks `ResolvingComment`
- [x] **7.19** Connect-session permission classification tests cover both read-write and downgraded read-only paths

**UI wiring tests:**

- [x] **7.15** Live dashboard triage actions call services only — no direct Graph calls
- [x] **7.16** Disabled-reasons panel updates reason text when context changes

### Workstream 8: Dashboard UX Hardening (Completed Additions)

- [x] **8.1** Add guided 3-step incident resolution workflow in Action Status panel (determination → resolving comment → confirm)
- [x] **8.2** Lock panel focus to resolution panel during active resolution workflow, then restore previous panel on complete/cancel
- [x] **8.3** Add panel navigation with `PgUp/PgDn` while preserving existing `Tab`/`Shift+Tab` model
- [x] **8.4** Add resolution-step navigation with `PgUp/PgDn`
- [x] **8.5** Change dashboard exit to `Ctrl+Q` and reserve `Esc` for cancel/back in modal workflows
- [x] **8.6** Convert action shortcuts to `Alt+` combinations and disable shortcut capture during free-text input
- [x] **8.7** Add active-panel border highlighting in theme color

### Workstream 9: Permission-Aware Degraded Mode (Completed Additions)

- [x] **9.1** Add runtime permission-health model to context session state
- [x] **9.2** Implement scope-based write sufficiency classification from Graph context (minimum: `SecurityIncident.ReadWrite.All`)
- [x] **9.3** Parse Graph forbidden messages to capture required and available permissions and update permission health
- [x] **9.4** Downgrade mutating capabilities to read-only action sets when permissions are insufficient
- [x] **9.5** Render dashboard logo in red when write permissions are insufficient

---

## Implementation Order

1. Implement policy file schema and loader
2. Implement and test policy validator
3. Implement status/classification mapping helpers
4. Implement incident triage service with resolving comment fallback
5. Implement alert triage service for all three statuses
6. Implement assign-target resolver with mail → UPN fallback
7. Wire live dashboard to new services
8. Add dedicated disabled-reasons panel
9. Add and enforce confirmation policy

---

## Acceptance Criteria

- [x] Incident triage statuses, classifications, determinations, and resolving comment fallback work in live dashboard
- [x] Alert status triage for New, In progress, and Resolved works in live dashboard
- [x] Confirmation behavior is policy-driven and validated by tests
- [x] Disabled-reasons panel is always visible and context-aware
- [x] Resolved incident updates use Graph `resolvingComment` while normal comments use incident comment endpoint
- [x] Dashboard supports keyboard-safe workflow controls (`Alt+` shortcuts, `Ctrl+Q`, `PgUp/PgDn`) and resolution focus locking
- [x] Permission-aware degraded mode updates capabilities and visual state (red logo) when write permissions are insufficient
- [ ] Policy edits are protected by unit tests that catch typos and invalid entries
- [x] UI layer performs no direct Graph mutation calls

---

## Manual Validation Checklist

- [x] Change incident status from Active to In progress
- [x] Resolve incident without entering a comment — verify default comment is applied
- [ ] Update classification and determination using allowed options
- [x] Update alert to New, In progress, and Resolved
- [ ] Validate assign-to-me uses `mail` first and `userPrincipalName` when mail is empty
- [ ] Trigger a capability restriction and confirm disabled reason appears in the dedicated panel
- [x] Validate confirmation prompt appears for actions flagged as disruptive

---

## New Functions

| Function | Visibility | Purpose |
|----------|------------|---------|
| `Set-XdrIncidentTriage` | Public | Full incident triage: status, classification, determination, comment, assignment |
| `Set-XdrAlertStatus` | Public | Alert status update |
| `Get-XdrTriageOptions` | Public | Returns available triage options from policy |
| `Get-XdrTriagePolicy` | Private | Loads and returns parsed triage policy |
| `Test-XdrTriageValue` | Private | Validates a display value exists in a policy map |
| `Resolve-XdrGraphEnumValue` | Private | Translates display label to Graph enum value |
| `Get-XdrAssignTargetIdentity` | Private | Resolves analyst identity (mail → UPN fallback) |
| `Get-XdrActionSafetyPolicy` | Private | Returns safety policy entry for a given action |
| `Test-XdrActionSafetyPolicy` | Private | Returns whether action requires confirmation |
| `Get-XdrActionDisableReasons` | Private | Returns list of reasons an action is unavailable |

---

## Relevant Files

- [config/triage-policy.json](../config/triage-policy.json) — triage and safety policy
- [Public/Set-XdrIncidentTriage.ps1](../Public/Set-XdrIncidentTriage.ps1) — incident triage service
- [Public/Set-XdrAlertStatus.ps1](../Public/Set-XdrAlertStatus.ps1) — alert triage service
- [Private/Get-XdrTriagePolicy.ps1](../Private/Get-XdrTriagePolicy.ps1) — policy loader
- [Public/Connect-XdrSession.ps1](../Public/Connect-XdrSession.ps1) — permission-health detection and capability downgrade logic
- [Private/Invoke-XdrOperation.ps1](../Private/Invoke-XdrOperation.ps1) — forbidden-permission parsing and runtime permission updates
- [Public/Start-PwshXdrLiveDashboard.ps1](../Public/Start-PwshXdrLiveDashboard.ps1) — action/status UI, resolution workflow, keyboard UX, visual permission cues
- [Tests/Connect-XdrSession.Tests.ps1](../Tests/Connect-XdrSession.Tests.ps1) — scope-based permission classification tests
- [Invoke-PwshXDRDashboard.ps1](../Invoke-PwshXDRDashboard.ps1) — live dashboard wiring target
