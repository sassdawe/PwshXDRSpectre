# Phase 2 — Incident and Alert Operations

**Status**: ⚪ Not Started  
**Depends on**: [Phase 1 — Foundation](phase-1-foundation.md)  
**Blocks**: Phase 3  
**Last updated**: 2026-04-21

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

- [ ] **1.1** Create `config/triage-policy.json` with the following minimum sections:
  - `incidentStatusMap` — display label to Graph enum value
  - `alertStatusMap` — display label to Graph enum value
  - `classifications` — list of available classification options
  - `determinations` — list of available determination options
  - `defaultResolvingComment` — auto-fill text for resolved incidents without comments
  - `safetyPolicy` — action confirmation requirements table
- [ ] **1.2** Implement `Private/Get-XdrTriagePolicy.ps1` — loads and returns the parsed policy from `config/triage-policy.json`
- [ ] **1.3** Implement `Private/Test-XdrTriageValue.ps1` — validates that a given display value exists in the policy map
- [ ] **1.4** Implement `Private/Resolve-XdrGraphEnumValue.ps1` — translates a display label to its Graph enum value using the policy map
- [ ] **1.5** Implement policy schema validation with the following rules:
  - Required keys must exist
  - No duplicate display labels within a map
  - No duplicate Graph enum values within a map
  - All safety policy levels must be valid
  - Unknown actions in safety policy fail validation
  - Status and classification entries match allowed schema

### Workstream 2: Incident Triage Service

- [ ] **2.1** Implement `Public/Set-XdrIncidentTriage.ps1` with support for:
  - Status (`active`, `inProgress`, `resolved`)
  - Classification
  - Determination
  - AssignedTo
  - Comment (with auto-fill fallback on resolve)
- [ ] **2.2** Implement `Private/Get-XdrAssignTargetIdentity.ps1` — resolves analyst identity using `mail` first, then `userPrincipalName` as fallback
- [ ] **2.3** Ensure resolving-comment auto-fill triggers only when comment is missing and status is `resolved`
- [ ] **2.4** Ensure service builds proper Graph PATCH payload before calling `Invoke-XdrOperation`
- [ ] **2.5** Implement `Public/Get-XdrTriageOptions.ps1` — returns available status, classification, and determination options from policy

### Workstream 3: Alert Triage Service

- [ ] **3.1** Implement `Public/Set-XdrAlertStatus.ps1` with support for `new`, `inProgress`, `resolved`
- [ ] **3.2** Ensure service builds proper Graph PATCH payload before calling `Invoke-XdrOperation`
- [ ] **3.3** Validate the requested status exists in `alertStatusMap` before executing

### Workstream 4: Action Safety Policy

- [ ] **4.1** Implement `Private/Get-XdrActionSafetyPolicy.ps1` — returns the safety policy for a given action name
- [ ] **4.2** Implement `Private/Test-XdrActionSafetyPolicy.ps1` — returns whether an action requires confirmation
- [ ] **4.3** Implement `Private/Get-XdrActionDisableReasons.ps1` — returns a list of reasons why an action is unavailable, given current context and capabilities
- [ ] **4.4** Wire confirmation prompts for all actions flagged as `confirm: true` in the policy

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

- [ ] **5.1** Add a dedicated UI panel that always shows action availability and reason text
- [ ] **5.2** Populate reason text from these sources:
  - Missing capability
  - Missing selection context (no incident/alert selected)
  - Invalid transition for current status
  - Policy disabled
- [ ] **5.3** Panel updates whenever selected incident, alert, or action changes
- [ ] **5.4** Panel visually distinguishes `Blocked` from `Warning` states

### Workstream 6: Dashboard Wiring

- [ ] **6.1** Wire menu dashboard (`Start-PwshXdrDashboard`) to all triage services
- [ ] **6.2** Wire live dashboard (`Start-PwshXdrLiveDashboard`) to all triage services
- [ ] **6.3** Confirm no dashboard file calls Graph cmdlets directly for any triage operation
- [ ] **6.4** Confirm disabled-reasons panel is rendered in both dashboard modes

### Workstream 7: Tests

**Unit tests:**

- [ ] **7.1** `Tests/Get-XdrTriagePolicy.Tests.ps1` — policy loader parses valid config
- [ ] **7.2** Policy validator rejects typos and unknown values
- [ ] **7.3** Incident status display-to-Graph mapping works for all three statuses
- [ ] **7.4** Alert status display-to-Graph mapping works for all three statuses
- [ ] **7.5** Classification and determination mapping resolves initial options
- [ ] **7.6** Missing resolving comment on resolved incident auto-fills default text
- [ ] **7.7** Assign target resolver uses `mail` first and `userPrincipalName` as fallback
- [ ] **7.8** Safety policy correctly flags confirm-required actions
- [ ] **7.9** Disabled reason generator returns deterministic reasons

**Mocked service tests:**

- [ ] **7.10** Incident triage service builds proper payload for each status
- [ ] **7.11** Incident resolve flow includes default comment when field is empty
- [ ] **7.12** Alert triage service builds proper payload for each status
- [ ] **7.13** Capability failure returns structured non-terminating error
- [ ] **7.14** Invalid policy values fail closed before any Graph call is made

**UI wiring tests:**

- [ ] **7.15** Menu dashboard triage actions call services only — no direct Graph calls
- [ ] **7.16** Live dashboard triage actions call services only — no direct Graph calls
- [ ] **7.17** Disabled-reasons panel updates reason text when context changes

---

## Implementation Order

1. Implement policy file schema and loader
2. Implement and test policy validator
3. Implement status/classification mapping helpers
4. Implement incident triage service with resolving comment fallback
5. Implement alert triage service for all three statuses
6. Implement assign-target resolver with mail → UPN fallback
7. Wire menu dashboard to new services
8. Wire live dashboard to new services
9. Add dedicated disabled-reasons panel
10. Add and enforce confirmation policy

---

## Acceptance Criteria

- [ ] Incident triage statuses, classifications, determinations, and resolving comment fallback work in both dashboards
- [ ] Alert status triage for New, In progress, and Resolved works in both dashboards
- [ ] Confirmation behavior is policy-driven and validated by tests
- [ ] Disabled-reasons panel is always visible and context-aware
- [ ] Policy edits are protected by unit tests that catch typos and invalid entries
- [ ] UI layer performs no direct Graph mutation calls

---

## Manual Validation Checklist

- [ ] Change incident status from Active to In progress
- [ ] Resolve incident without entering a comment — verify default comment is applied
- [ ] Update classification and determination using allowed options
- [ ] Update alert to New, In progress, and Resolved
- [ ] Validate assign-to-me uses `mail` first and `userPrincipalName` when mail is empty
- [ ] Trigger a capability restriction and confirm disabled reason appears in the dedicated panel
- [ ] Validate confirmation prompt appears for actions flagged as disruptive

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

- [config/triage-policy.json](../config/triage-policy.json) — triage and safety policy (to be created)
- [Public/Set-XdrIncidentTriage.ps1](../Public/Set-XdrIncidentTriage.ps1) — incident triage service (to be created)
- [Public/Set-XdrAlertStatus.ps1](../Public/Set-XdrAlertStatus.ps1) — alert triage service (to be created)
- [Private/Get-XdrTriagePolicy.ps1](../Private/Get-XdrTriagePolicy.ps1) — policy loader (to be created)
- [PwshXDRDashboard.ps1](../PwshXDRDashboard.ps1) — menu dashboard wiring target
- [Invoke-PwshXDRDashboard.ps1](../Invoke-PwshXDRDashboard.ps1) — live dashboard wiring target
