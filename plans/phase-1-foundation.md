# Phase 1 — Foundation and Architecture

**Status**: 🟡 In Progress  
**Depends on**: —  
**Blocks**: All later phases  
**Last updated**: 2026-04-21

---

## Goals

1. Replace the current script-global, UI-coupled flow with a small internal platform that later phases can build on safely.
2. Separate data retrieval, action execution, state management, and rendering so the simple dashboard and live dashboard stop duplicating logic.
3. Introduce stable internal contracts for runtime context, operation results, and view models before incident actions, hunting, and memory persistence expand the surface area.

## Scope

**In scope**: Runtime context model, module/function boundaries, backend service layer, error/result contract, thin entry-point scripts, and the first test harness.

**Out of scope**: New analyst actions, KQL execution, memory persistence, and major layout redesign beyond what is needed to consume shared services.

---

## Tasks

### Workstream 1: Runtime Context Model

Create a single in-memory context object that becomes the authoritative state for both dashboards.

- [x] **1.1** Create `Private/New-XdrRuntimeContext.ps1` with the full context shape
  - `Session`: TenantId, ClientId, Analyst, IsConnected, StartedAt
  - `Selection`: Incident, Alert, Entity, Action, Panel
  - `Data`: Incidents, Alerts, Entities, QueryCatalog, LastRefresh
  - `Ui`: Mode, ThemeColor, StatusMessage, RefreshIntervalMs
  - `Capabilities`: IncidentActions, AlertActions, UserActions, DeviceActions, FileActions
  - `Diagnostics`: LastError, LastOperation, Warnings
- [ ] **1.2** Add focused selection setters so UI code never mutates context keys directly
- [x] **1.3** Remove `$Script:metaIncidents` as primary selection store — derive menu choices from `Context.Data.Incidents` instead

### Workstream 2: Module and Function Layout

Refactor the current flat-script structure into a PowerShell module with thin entry scripts.

**Target module structure:**

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

- [x] **2.1** Move Graph connection and analyst lookup out of `PwshXDRDashboard.ps1` into session functions (`Connect-XdrSession`, `Get-XdrCurrentUser`)
- [x] **2.2** Split `Update-IncidentTable.ps1` into two layers: data retrieval (`Get-XdrIncidents`) and presentation formatting (`Format-XdrIncidentTable`)
- [ ] **2.3** Move reusable panel helpers from `Invoke-PwshXDRDashboard.ps1` into private UI helper functions
- [x] **2.4** Update `PwshXDRSpectre.psm1` to dot-source all Public and Private functions
- [x] **2.5** Keep existing script files (`PwshXDRDashboard.ps1`, `Invoke-PwshXDRDashboard.ps1`) as compatibility shims that import the module and delegate to public functions

### Workstream 3: Service Layer and Data Contracts

Introduce a service layer so UI code never calls Graph cmdlets directly.

**View model contracts:**

| Model | Fields |
|-------|--------|
| Incident | `IncidentId`, `DisplayName`, `Status`, `Severity`, `AssignedTo`, `Determination`, `CreatedDateTime`, `AlertCount`, `TenantId`, `RawObject` |
| Alert | `AlertId`, `Title`, `Status`, `Severity`, `CreatedDateTime`, `AlertWebUrl`, `IncidentId`, `RawObject` |
| Menu option | `Label`, `Value`, `Description`, `IsEnabled` |

- [x] **3.1** Implement `Connect-XdrSession` — connect to Microsoft Graph and populate `Context.Session`
- [x] **3.2** Implement `Get-XdrIncidents` — retrieve incidents and return normalized incident view models
- [x] **3.3** Implement `Get-XdrAlerts` — retrieve alert details for the selected incident on demand
- [x] **3.4** Implement `Get-XdrCurrentUser` — resolve `/me` once and cache in `Context.Session.Analyst`
- [x] **3.5** Implement `ConvertTo-XdrIncidentViewModel` — normalize raw Graph incident objects to the incident view model
- [x] **3.6** Implement `ConvertTo-XdrAlertViewModel` — normalize raw Graph alert objects to the alert view model
- [x] **3.7** Replace all direct raw Graph object shaping in `PwshXDRDashboard.ps1`, `Invoke-PwshXDRDashboard.ps1`, and `Update-IncidentTable.ps1` with view model converters

### Workstream 4: Operation Result and Error Contract

Every backend call returns a predictable envelope instead of throwing UI-specific text.

**Result envelope shape:**

```powershell
[pscustomobject]@{
    Success    = $true
    Operation  = 'Get-XdrIncidents'
    Message    = 'Retrieved incidents successfully.'
    Data       = $incidents
    Error      = $null
    Metadata   = [ordered]@{
        TenantId   = $Context.Session.TenantId
        DurationMs = 123
        Timestamp  = Get-Date
    }
}
```

- [x] **4.1** Implement `Invoke-XdrOperation` — wrap Graph and REST execution in one place, return the result envelope
- [x] **4.2** Implement `New-XdrErrorRecord` — create consistent PowerShell error records with category, target object, and user-safe message
- [x] **4.3** Update all UI flows to render `Message` and `Diagnostics.LastError` instead of catching broad exceptions with generic text
- [ ] **4.4** Ensure `Invoke-XdrOperation` fails closed when capability checks are ambiguous or unavailable

### Workstream 5: Entry-Point Consolidation

Both entry scripts become thin orchestration layers backed by the same services.

- [x] **5.1** Implement `Start-PwshXdrDashboard` (menu-driven) using shared services and context
- [x] **5.2** Implement `Start-PwshXdrLiveDashboard` (live layout) using shared services and context
- [x] **5.3** Confirm both entry styles share the same session connection flow
- [x] **5.4** Confirm both entry styles share the same incident and alert retrieval functions
- [ ] **5.5** Confirm both entry styles share the same selection/context update path
- [x] **5.6** Confirm both entry styles share the same error/result handling

### Workstream 6: Testing Baseline

Add a Pester test suite covering non-UI logic so later phases can evolve without breaking the platform.

- [x] **6.1** `Tests/New-XdrRuntimeContext.Tests.ps1` — returns expected structure and defaults
- [x] **6.2** `Tests/ConvertTo-XdrIncidentViewModel.Tests.ps1` — preserves all required incident fields
- [x] **6.3** `Tests/ConvertTo-XdrAlertViewModel.Tests.ps1` — preserves all required alert fields
- [x] **6.4** `Tests/Invoke-XdrOperation.Tests.ps1` — returns expected success and failure envelopes
- [x] **6.5** `Tests/Test-XdrCapability.Tests.ps1` — fails closed when input is missing or malformed
- [x] **6.6** `Tests/EntryScripts.Tests.ps1` — entry scripts pass parameters correctly into public functions
- [x] **6.7** All tests pass via `Invoke-Pester`

---

## Implementation Order

1. Build `New-XdrRuntimeContext` and session functions first (Workstream 1, then 3.1 and 3.4)
2. Extract incident and alert retrieval into service functions (Workstream 3.2–3.3)
3. Add view-model converters and replace direct shaping in UI scripts (Workstream 3.5–3.7)
4. Introduce the operation/error wrapper (Workstream 4)
5. Convert both entry-point scripts into thin callers (Workstream 5)
6. Refactor module layout so dot-sourcing is clean (Workstream 2)
7. Write and pass all Pester tests (Workstream 6)
8. Update README to reflect new architecture

---

## Acceptance Criteria

- [x] No UI file calls Microsoft Graph cmdlets directly — service functions own all external calls
- [x] No selection state depends on ad hoc script-global variables such as `$Script:metaIncidents`
- [x] Both dashboards load incidents and alert details through the same backend functions
- [x] Errors from Graph/auth/rendering are surfaced as structured status information, not generic catch-all text
- [x] The repository has a repeatable test entry point for Phase 1 logic (`Invoke-Pester`)

---

## Deliverables

1. A PowerShell module with clear Public/Private function boundaries
2. One authoritative runtime context object shared by both dashboards
3. Normalized incident and alert view models
4. Standardized operation results and error handling
5. Both entry scripts runnable with current parameters
6. A minimal Pester suite validating the new foundation
7. Updated README with new architecture overview, setup instructions, and permission changes

---

## Risks and Tradeoffs

| Risk | Mitigation |
|------|------------|
| Full module conversion adds initial overhead | Not doing it makes Phases 3–5 slower and riskier due to duplicated logic |
| Breaking current usage | Accepted — internal tool in active development; no compatibility required |
| Over-designing entity models | Deferred to Phase 3 — only define incident and alert contracts here |

---

## Relevant Files

- [PwshXDRDashboard.ps1](../PwshXDRDashboard.ps1) — current action loop to evolve into modular dispatcher-backed flow
- [Invoke-PwshXDRDashboard.ps1](../Invoke-PwshXDRDashboard.ps1) — live TUI layout/event loop
- [Update-IncidentTable.ps1](../Update-IncidentTable.ps1) — incident/alert shaping logic to split
- [README.md](../README.md) — update setup, permissions, and architecture overview
