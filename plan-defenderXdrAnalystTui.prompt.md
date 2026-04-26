## Plan: Defender XDR Analyst TUI

Build a modular PowerShell terminal app on PSSpectreConsole that supports full analyst workflows: incident/alert triage, user/device/file containment, context-aware KQL hunting from JSON files, and persistent workflow memory for agent-style operations.
I used your decisions: Graph + direct REST, single active tenant UX, repo-based query JSON, and full containment scope for v1.

**Steps**
1. Phase 1: Foundation and architecture (blocks all later phases)
1. Define a shared runtime context model for active tenant, selected incident/alert/entity, current UI panel, and session metadata.
2. Refactor current script logic into reusable modules (data access, action dispatch, UI rendering, and state handling).
3. Add consistent error envelopes and operator-safe feedback paths so the TUI can distinguish auth/API/data issues.
4. Unify both dashboard entry styles behind the same backend functions to avoid drift.

2. Phase 2: Incident and alert operations (depends on Phase 1)
1. Implement complete incident triage actions: assign/unassign, status, classification, determination, and comments.
2. Implement alert triage actions with drill-down details and status updates.
3. Add confirmations for impactful actions and clear rollback/result messaging.
4. Add permission checks with graceful degraded behavior if required delegated permissions are missing.

3. Phase 3: Entity pivots and containment actions (depends on Phase 2; several tasks can run in parallel)
1. Build entity extraction from incident/alert evidence and normalize affected users/devices/files.
2. User containment (parallel): revoke sessions and optional disable-account flow.
3. Device containment (parallel): isolate device and run supported remediation actions.
4. File containment (parallel): quarantine file / block indicator workflows.
5. Persist each executed action and result into action history.

4. Phase 4: Hunting query engine from JSON (depends on Phase 1; can overlap late Phase 3)
1. Add repo query catalog folder and JSON schema: id, name, description, requiredContext, parameters, KQL text, and display metadata.
2. Implement startup loader + schema validation with actionable parse errors.
3. Implement context binding so selected incident/device/user variables are injected into query parameters safely.
4. Add TUI flow for query selection, rendered preview, execution, result navigation, and pivot-back to entities.
5. Record query run metadata (query id, context, timing, status, row count) in workflow memory.

5. Phase 5: Agent workflow memory store (depends on Phases 1 and 4 for full value)
1. Implement local JSON persistence for checkpoints, context snapshots, action history, and query runs.
2. Use append-only history records with versioning/retention rules.
3. Provide store APIs: checkpoint save/load, history append, query run append, retention cleanup.
4. Restore last analyst context on startup (tenant, incident, recent actions, recent query runs).

6. Phase 6: UX hardening, testing, and docs (depends on all prior phases)
1. Expand layout to dedicated panes for Incidents, Alerts, Entities, Actions, Query Catalog, Query Results, and Activity Log.
2. Add keyboard help/status indicators and non-blocking feedback for long-running operations.
3. Add Pester tests for JSON schema validation, context interpolation, memory store behavior, and action payload builders.
4. Validate end-to-end in a test tenant and verify audit evidence in Defender portal.
5. Update usage and permissions documentation.

**Phase 1 Detailed Plan**

**Phase 1 goals**
1. Replace the current script-global, UI-coupled flow with a small internal platform that later phases can build on safely.
2. Separate data retrieval, action execution, state management, and rendering so the simple dashboard and live dashboard stop duplicating logic.
3. Introduce stable internal contracts for runtime context, operation results, and view models before incident actions, hunting, and memory persistence expand the surface area.

**Phase 1 scope**
1. In scope: runtime context model, module/function boundaries, backend service layer, error/result contract, thin entry-point scripts, and the first test harness.
2. Out of scope: new analyst actions, KQL execution, memory persistence, and major layout redesign beyond what is needed to consume shared services.

**Phase 1 workstreams**

### 1. Runtime context model

Create a single in-memory context object that becomes the authoritative state for dashboard entry and live dashboard rendering flows.

Minimum fields:
1. `Session`: active tenant id, client id, current analyst identity, connection status, started-at timestamp.
2. `Selection`: selected incident, selected alert, selected entity, selected action, current panel name.
3. `Data`: cached incidents, cached alerts for selected incident, cached entities, query catalog placeholder, last refresh timestamp.
4. `Ui`: color palette, current mode (`menu` or `live`), status message, last notification, refresh interval.
5. `Capabilities`: discovered permissions and supported actions for current tenant/session.
6. `Diagnostics`: last error, last successful operation, transient warnings.

Suggested shape:

```powershell
[ordered]@{
	Session = [ordered]@{
		TenantId = $TenantId
		ClientId = $ClientId
		Analyst = $null
		IsConnected = $false
		StartedAt = Get-Date
	}
	Selection = [ordered]@{
		Incident = $null
		Alert = $null
		Entity = $null
		Action = $null
		Panel = 'incidents'
	}
	Data = [ordered]@{
		Incidents = @()
		Alerts = @()
		Entities = @()
		QueryCatalog = @()
		LastRefresh = $null
	}
	Ui = [ordered]@{
		Mode = 'menu'
		ThemeColor = 'Orange1'
		StatusMessage = $null
		RefreshIntervalMs = 200
	}
	Capabilities = [ordered]@{
		IncidentActions = @()
		AlertActions = @()
		UserActions = @()
		DeviceActions = @()
		FileActions = @()
	}
	Diagnostics = [ordered]@{
		LastError = $null
		LastOperation = $null
		Warnings = @()
	}
}
```

Implementation tasks:
1. Add a constructor function such as `New-XdrRuntimeContext`.
2. Add focused setters/getters for selection updates rather than mutating script-scoped variables everywhere.
3. Remove dependence on `$Script:metaIncidents` as the primary selection store and derive menu choices from `Context.Data.Incidents` view models.

### 2. Module and function layout

Refactor the current flat-script structure into a PowerShell module with thin entry scripts.

Proposed structure:

```text
PwshXDRSpectre.psm1
Public/
  Start-PwshXdrDashboard.ps1
  Start-PwshXdrLiveDashboard.ps1
  Connect-XdrSession.ps1
Private/
  New-XdrRuntimeContext.ps1
  Get-XdrCurrentUser.ps1
  Get-XdrIncidents.ps1
  Get-XdrAlerts.ps1
  ConvertTo-XdrIncidentViewModel.ps1
  ConvertTo-XdrAlertViewModel.ps1
  Invoke-XdrOperation.ps1
  Write-XdrStatusMessage.ps1
  Test-XdrCapability.ps1
  New-XdrErrorRecord.ps1
```

Refactor targets from current files:
1. Move Graph connection and analyst lookup out of dashboard entry logic into session functions.
2. Split [Update-IncidentTable.ps1](Update-IncidentTable.ps1#L1) into two layers: data retrieval and presentation formatting.
3. Move the reusable panel helpers from live dashboard entry logic into private UI helper functions.
4. Keep existing script files as wrappers that import the module and call public functions, so current usage does not break immediately.

### 3. Service layer and data contracts

Introduce a service layer so UI code never calls `Get-MgSecurityIncident`, `Get-MgSecurityAlertV2`, or `Update-MgSecurityIncident` directly.

Service responsibilities:
1. `Connect-XdrSession`: connect to Microsoft Graph and populate `Context.Session`.
2. `Get-XdrIncidents`: retrieve incidents for the active tenant and return normalized objects.
3. `Get-XdrAlerts`: retrieve alert details for the selected incident only when needed.
4. `Get-XdrCurrentUser`: resolve `/me` once and cache it in context.
5. `Invoke-XdrOperation`: central wrapper that executes Graph calls, normalizes success/failure, and updates diagnostics.

View model contracts to define early:
1. Incident view model: `IncidentId`, `DisplayName`, `Status`, `Severity`, `AssignedTo`, `Determination`, `CreatedDateTime`, `AlertCount`, `TenantId`, `RawObject`.
2. Alert view model: `AlertId`, `Title`, `Status`, `Severity`, `CreatedDateTime`, `AlertWebUrl`, `IncidentId`, `RawObject`.
3. Menu option model: `Label`, `Value`, `Description`, `IsEnabled`.

This solves the current problem where the same raw Graph objects are shaped differently across dashboard flows and [Update-IncidentTable.ps1](Update-IncidentTable.ps1#L21).

### 4. Operation result and error contract

Every backend call should return a predictable envelope instead of throwing UI-specific text directly.

Suggested result shape:

```powershell
[pscustomobject]@{
	Success = $true
	Operation = 'Get-XdrIncidents'
	Message = 'Retrieved incidents successfully.'
	Data = $incidents
	Error = $null
	Metadata = [ordered]@{
		TenantId = $Context.Session.TenantId
		DurationMs = 123
		Timestamp = Get-Date
	}
}
```

Implementation tasks:
1. Add `Invoke-XdrOperation` to wrap Graph and REST execution in one place.
2. Add `New-XdrErrorRecord` to create consistent PowerShell error records with category, target object, and user-safe message.
3. Update UI flows so they render `Message` and `Diagnostics.LastError` instead of catching broad exceptions and printing generic status text.
4. Fail closed when capability checks are ambiguous or unavailable.

### 5. Entry-point consolidation

The two existing entry points should become thin orchestration layers.

Target split:
1. `Start-PwshXdrDashboard`: menu-driven experience using shared services and shared context.
2. `Start-PwshXdrLiveDashboard`: live layout experience using the same shared services and shared context.
3. Existing scripts remain compatibility shims that call the new public functions with the current parameters.

Phase 1 deliverable here is not a final UI redesign. The deliverable is that both entry styles use the same:
1. session connection flow,
2. incident retrieval functions,
3. alert retrieval functions,
4. selection/context updates,
5. error/result handling.

### 6. Testing baseline

Add a first Pester test suite focused on non-UI logic so later phases can change features without breaking the platform.

Initial test targets:
1. `New-XdrRuntimeContext` returns the expected structure and defaults.
2. Incident and alert view-model conversion functions preserve required fields.
3. `Invoke-XdrOperation` returns the expected success/failure envelope.
4. Capability checks fail closed when input is missing or malformed.
5. Entry scripts pass parameters correctly into public functions.

Suggested test layout:

```text
Tests/
  New-XdrRuntimeContext.Tests.ps1
  ConvertTo-XdrIncidentViewModel.Tests.ps1
  ConvertTo-XdrAlertViewModel.Tests.ps1
  Invoke-XdrOperation.Tests.ps1
```

**Phase 1 implementation order**
1. Add Pester coverage for the new internal contracts.
2. Build `New-XdrRuntimeContext` and session functions first.
3. Extract incident and alert retrieval into service functions.
4. Add view-model converters and replace direct shaping in UI scripts.
5. Introduce the operation/error wrapper.
6. Convert both entry-point scripts into thin callers of shared public functions.
7. Make sure all tests pass and update documentation to reflect the new architecture and any parameter changes. 

**Phase 1 deliverables**
1. A reusable module or dot-sourced function set with clear public/private boundaries.
2. One authoritative runtime context object shared by both dashboards.
3. Normalized incident and alert models.
4. Standardized operation results and error handling.
5. Existing entry scripts still runnable with the current parameters.
6. A minimal Pester suite validating the new foundation.
7. Updated README with new architecture overview, setup instructions, and any changes to usage or permissions.

**Phase 1 acceptance criteria**
1. No UI file calls Microsoft Graph cmdlets directly; service functions own external calls.
2. No selection state depends on ad hoc script-global variables such as `$Script:metaIncidents`.
3. Both dashboards can load incidents and alert details through the same backend functions.
4. Errors from Graph/auth/rendering are surfaced as structured status information, not generic catch-all text.
5. The repository has a repeatable test entry point for Phase 1 logic.

**Phase 1 risks and tradeoffs**
1. Full module conversion adds initial overhead, but not doing it will make later phases slower and riskier because containment, hunting, and persistence will otherwise duplicate logic across two UIs.
2. We drop compatibility and embrace breaking current usage while the module boundary stabilizes.
3. Avoid over-designing entity models in Phase 1; only define incident and alert contracts now, then add user/device/file models in Phase 3.

**Relevant files**
- [src/Public/Start-PwshXdrLiveDashboard.ps1](src/Public/Start-PwshXdrLiveDashboard.ps1#L1) - live TUI layout/event loop to extend for analyst workflow panes
- [Update-IncidentTable.ps1](Update-IncidentTable.ps1#L1) - incident/alert shaping logic to split into data layer + presentation layer
- [README.md](README.md#L1) - update setup, permissions, query JSON format, and memory-store behavior

**Verification**
1. Pester unit tests for query schema validation, context binding, and memory store read/write/retention.
2. Integration tests for incident/alert updates against a test tenant.
3. Integration tests for user/device/file containment actions (with audit log confirmation).
4. Manual TUI flow validation: incident -> alert -> entity -> hunting query -> action loop.
5. Restart/resume validation to confirm workflow memory restores context and history.
6. Security checks to ensure no secrets are written to persisted memory data.

**Decisions captured**
- API approach: Microsoft Graph cmdlets + direct Graph REST when cmdlets are insufficient.
- v1 scope includes incident triage, alert triage, user containment, device containment, file actions.
- Hunting queries are stored in a repository folder as JSON.
- Tenant model is single active tenant for v1.
- Memory store persists checkpoints, entity context, action history, and query-run metadata.
- We don't need backwards compatibility with the old script structure since this is an internal tool in active development. We can break and refactor as needed to build a stable foundation for later phases.

## Phase 2 Detailed Implementation and Test Plan

This section locks Phase 2 planning based on confirmed answers. It does not start implementation.

### Phase 2 scope lock

1. Incident triage operations:
1. Status updates supported:
1. Active
2. In progress
3. Resolved
2. Graph value mapping should normalize to platform values:
1. active
2. inProgress
3. resolved
3. Classification and determination options exposed initially:
1. Unclassified
2. True positive / Malware
3. False positive / Not malicious
4. Keep classification and determination extendable via configuration file.
5. If incident is resolved without analyst input comment, auto-fill:
1. Resolved using PwshXDRSpectre
6. Assign to me identity fallback order:
1. mail
2. userPrincipalName

2. Alert triage operations:
1. Status updates supported:
1. New
2. In progress
3. Resolved
2. Graph value mapping should normalize to platform values:
1. new
2. inProgress
3. resolved

3. UX and safety behavior:
1. Disabled and unsupported action reasons must always be visible in a dedicated panel.
2. Potentially disruptive actions must be confirmation-gated via policy table.
3. Confirmation policy must be extendable in configuration and validated by tests.

### Proposed Phase 2 module additions

Public services:
1. Set-XdrIncidentTriage
2. Set-XdrAlertStatus
3. Get-XdrTriageOptions

Private helpers:
1. Get-XdrTriagePolicy
2. Test-XdrTriageValue
3. Resolve-XdrGraphEnumValue
4. Get-XdrAssignTargetIdentity
5. Get-XdrActionSafetyPolicy
6. Test-XdrActionSafetyPolicy
7. Get-XdrActionDisableReasons

### Configuration design for extendability

Use a repository-stored policy file for triage and safety mappings so edits do not require code changes.

Recommended file path:
1. config/triage-policy.json

Minimum sections:
1. incidentStatusMap
2. alertStatusMap
3. classifications
4. determinations
5. defaultResolvingComment
6. safetyPolicy

Validation requirements:
1. Required keys must exist.
2. No duplicate display labels.
3. No duplicate Graph values.
4. All safety policy levels must be valid.
5. Unknown actions in safety policy should fail validation.
6. Status and classification entries must match allowed schema.

### Recommended disruptive operations policy table

This is the default recommendation table. Keep editable in policy config.

| Action | Category | Recommended confirmation | Recommended wording |
|---|---|---|---|
| Assign incident to me | Incident triage | No | None |
| Clear incident assignment | Incident triage | Yes | Clear assignment from this incident? |
| Set incident status to Active | Incident triage | No | None |
| Set incident status to In progress | Incident triage | No | None |
| Set incident status to Resolved | Incident triage | Yes | Resolve this incident now? |
| Set incident classification | Incident triage | No | None |
| Set incident determination | Incident triage | No | None |
| Auto-fill resolving comment | Incident triage | No | None |
| Set alert status to New | Alert triage | Yes | Reopen this alert as New? |
| Set alert status to In progress | Alert triage | No | None |
| Set alert status to Resolved | Alert triage | Yes | Resolve this alert now? |

Notes:
1. Operations that can reopen or finalize triage are marked confirm by default.
2. This table should be loaded from configuration, not hardcoded in UI.

### Dedicated panel for disabled reasons

Phase 2 UI requirement:
1. Add a dedicated panel to show action availability and reason text.
2. Reason sources:
1. Missing capability
2. Missing selection context
3. Invalid transition for current status
4. Policy disabled

Panel behavior:
1. Always visible.
2. Updates whenever selected incident, alert, or action changes.
3. Should distinguish blocked versus warning states.

### Phase 2 implementation sequence

1. Implement policy file schema and loader.
2. Implement policy validator and tests.
3. Implement status/classification mapping helpers.
4. Implement incident triage service with resolving comment fallback.
5. Implement alert triage service for all three statuses.
6. Implement assign target resolver with mail then UPN fallback.
7. Wire menu dashboard to new services.
8. Wire live dashboard to new services.
9. Add dedicated disabled-reasons panel.
10. Add confirmation policy enforcement.

### Phase 2 test plan

Unit tests:
1. Policy loader parses valid config.
2. Policy validator rejects typos and unknown values.
3. Incident status display-to-Graph mapping works for all three statuses.
4. Alert status display-to-Graph mapping works for all three statuses.
5. Classification and determination mapping resolves initial options.
6. Missing resolving comment on resolved incident auto-fills default text.
7. Assign target resolver uses mail first and UPN as fallback.
8. Safety policy correctly flags confirm-required actions.
9. Disabled reason generator returns deterministic reasons.

Mocked service tests:
1. Incident triage service builds proper payload for each status.
2. Incident resolve flow includes default comment when needed.
3. Alert triage service builds proper payload for each status.
4. Capability failure returns structured non-terminating error.
5. Invalid policy values fail closed before any Graph call.

UI wiring tests:
1. Menu dashboard triage actions call services only.
2. Live dashboard triage actions call services only.
3. Dedicated panel updates reason text when context changes.

Manual validation checklist:
1. Change incident status Active to In progress.
2. Resolve incident without entering comment and verify default comment is applied.
3. Update classification and determination using allowed options.
4. Update alert to New, In progress, and Resolved.
5. Validate assign-to-me uses mail first and UPN fallback when mail is empty.
6. Trigger capability restriction and confirm disabled reason appears in dedicated panel.
7. Validate confirmation prompt appears for actions flagged as disruptive.

### Phase 2 completion criteria

1. Incident triage statuses, classifications, determinations, and resolving comment fallback work in both dashboards.
2. Alert status triage for New, In progress, and Resolved works in both dashboards.
3. Confirmation behavior is policy-driven and validated.
4. Disabled-reasons panel is always visible and context-aware.
5. Policy edits are protected by unit tests that catch typos and invalid entries.
6. UI layer performs no direct Graph mutation calls.