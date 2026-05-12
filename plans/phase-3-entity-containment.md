# Phase 3 — Entity Pivots and Containment Actions

**Status**: 🟡 In Progress  
**Depends on**: [Phase 2 — Incident and Alert Operations](phase-2-incident-alert-ops.md)  
**Blocks**: Phase 5 (action history)  
**Notes**: User, device, and file containment workstreams can run in parallel once entity extraction is complete  
**Last updated**: 2026-05-10

---

## Goals

1. Extract and normalize affected entities (users, devices, files) from incident/alert evidence.
2. Implement user containment actions: revoke active sessions and optionally disable account.
3. Implement device containment actions: isolate device and run supported remediation.
4. Implement file containment actions: quarantine file and block indicator workflows.
5. Capture every executed action and result in runtime action history using a redaction-ready schema compatible with Phase 5 encrypted persistence.

---

## Tasks

### Workstream 1: Entity Extraction and Normalization

Define user, device, and file view models before any containment work starts.

**Entity view models:**

| Model | Fields |
|-------|--------|
| User entity | `UserId`, `DisplayName`, `UserPrincipalName`, `AccountEnabled`, `RiskLevel`, `IncidentId`, `AlertId`, `RawObject` |
| Device entity | `DeviceId`, `DisplayName`, `OSPlatform`, `OnboardingStatus`, `HealthStatus`, `RiskScore`, `IncidentId`, `AlertId`, `RawObject` |
| File entity | `Sha256`, `FileName`, `Path`, `PrevalenceType`, `IncidentId`, `AlertId`, `RawObject` |

- [x] **1.1** Implement `Private/Get-XdrIncidentEntities.ps1` — extracts all entity references from incident evidence and alert details
- [ ] **1.2** Implement `Private/ConvertTo-XdrUserEntity.ps1` — normalizes raw user objects to the user entity view model
- [ ] **1.3** Implement `Private/ConvertTo-XdrDeviceEntity.ps1` — normalizes raw device objects to the device entity view model
- [ ] **1.4** Implement `Private/ConvertTo-XdrFileEntity.ps1` — normalizes raw file objects to the file entity view model
- [x] **1.5** Populate `Context.Data.Entities` when an incident or alert is selected
- [x] **1.6** Add entity list panel to TUI — shows extracted entities grouped by type

### Workstream 2: User Containment (parallel after 1.x)

- [ ] **2.1** Implement `Public/Invoke-XdrUserContainment.ps1` with the following actions:
  - Revoke all active sessions (`revokeSignInSessions` via Graph)
  - Disable account (`accountEnabled: false` via Graph)
- [ ] **2.2** Add confirmation gate for `DisableAccount` action (disruptive — requires confirmation)
- [ ] **2.3** Display current account status and last sign-in before presenting containment options
- [ ] **2.4** Record action and result in action history (see Workstream 5)
- [ ] **2.5** Update `Context.Capabilities.UserActions` to reflect available actions for selected user

### Workstream 3: Device Containment (parallel after 1.x)

- [ ] **3.1** Implement `Public/Invoke-XdrDeviceContainment.ps1` with the following actions:
  - Isolate device (full or selective via Defender for Endpoint REST API)
  - Unisolate device
  - Run antivirus scan
  - Collect investigation package
  - Restrict app execution
- [ ] **3.2** Add confirmation gate for `IsolateDevice` and `RestrictAppExecution` (disruptive actions)
- [ ] **3.3** Display current device isolation status and health before presenting containment options
- [ ] **3.4** Poll for action completion status after submission (async MDE machine action)
- [ ] **3.5** Record action and result in action history (see Workstream 5)
- [ ] **3.6** Update `Context.Capabilities.DeviceActions` to reflect available actions for selected device

### Workstream 4: File Containment (parallel after 1.x)

- [ ] **4.1** Implement `Public/Invoke-XdrFileContainment.ps1` with the following actions:
  - Quarantine file from a specific device
  - Block file indicator (add to tenant block list)
  - Remove file block indicator
- [ ] **4.2** Add confirmation gate for `BlockFileIndicator` and `QuarantineFile` (disruptive actions)
- [ ] **4.3** Display file prevalence and existing indicator status before presenting containment options
- [ ] **4.4** Record action and result in action history (see Workstream 5)
- [ ] **4.5** Update `Context.Capabilities.FileActions` to reflect available actions for selected file

### Workstream 5: Runtime Action History (Phase 5-Compatible)

Phase 3 owns in-memory action history and TUI rendering only.
Encrypted on-disk persistence is implemented in Phase 5.

- [ ] **5.1** Define action history record schema:
  - `ActionId` (GUID)
  - `ActionType` (e.g., `IsolateDevice`, `RevokeUserSessions`)
  - `EntityType` (`User`, `Device`, `File`, `Incident`, `Alert`)
  - `EntityId`
  - `ExecutedBy`
  - `ExecutedAt`
  - `Status` (`Submitted`, `Completed`, `Failed`)
  - `Result` (sanitized summary text only)
  - `IncidentId` (correlation)
  - `AlertId` (optional correlation)
- [ ] **5.2** Define field classes for compatibility with Phase 5 persistence:
  - `safe` fields allowed after encryption
  - `sensitive` fields requiring sanitization before persistence
  - `forbidden` fields (raw payloads, tokens, full stack traces) that are never recorded
- [ ] **5.3** Implement `Private/Add-XdrActionHistory.ps1` — appends a new action record to the in-memory history list
- [ ] **5.4** Populate `Context.Data` with a running `ActionHistory` list
- [ ] **5.5** Surface the last N actions in an activity log panel in the TUI
- [ ] **5.6** Ensure canceled confirmation prompts do not create executed action history records
- [ ] **5.7** Document handoff contract to Phase 5 encrypted store APIs

### Workstream 6: Tests

- [x] **6.1** `Tests/Get-XdrIncidentEntities.Tests.ps1` — entity extraction returns expected user/device/file objects
- [ ] **6.2** `Tests/ConvertTo-XdrUserEntity.Tests.ps1` — view model preserves required fields
- [ ] **6.3** `Tests/ConvertTo-XdrDeviceEntity.Tests.ps1` — view model preserves required fields
- [ ] **6.4** `Tests/ConvertTo-XdrFileEntity.Tests.ps1` — view model preserves required fields
- [ ] **6.5** `Tests/Invoke-XdrUserContainment.Tests.ps1` — builds correct Graph payloads; confirmation required for DisableAccount
- [ ] **6.6** `Tests/Invoke-XdrDeviceContainment.Tests.ps1` — builds correct MDE API payloads; confirmation required for IsolateDevice
- [ ] **6.7** `Tests/Invoke-XdrFileContainment.Tests.ps1` — builds correct indicator payloads; confirmation required for BlockFileIndicator
- [ ] **6.8** `Tests/Add-XdrActionHistory.Tests.ps1` — appends records correctly; all required fields populated
- [ ] **6.9** `Tests/Add-XdrActionHistory.Tests.ps1` — rejects forbidden fields and stores sanitized result summaries only
- [ ] **6.10** `Tests/Add-XdrActionHistory.Tests.ps1` — does not append executed records for canceled confirmations

---

## Acceptance Criteria

- [x] Entity extraction runs automatically when an incident or alert is selected
- [ ] All three containment types (user, device, file) are accessible from the TUI
- [ ] Disruptive actions require confirmation before execution
- [ ] Every executed action and its result is recorded in the in-memory action history
- [ ] Action history entries are redaction-ready and exclude forbidden sensitive fields
- [ ] Phase 3 writes no action history to disk; persistence is deferred to Phase 5 encrypted store APIs
- [ ] No containment function calls Graph or MDE APIs directly from UI code
- [ ] Capability panels reflect available actions based on entity state and permissions

---

## Manual Validation Checklist

- [ ] Select an incident with user evidence — verify user entities appear in the entity panel
- [ ] Revoke sessions for a test user — verify Graph call succeeds and action is recorded
- [ ] Disable a test account — verify confirmation prompt appears first
- [ ] Isolate a test device — verify MDE action is submitted and status is polled
- [ ] Block a file indicator — verify block is added to the tenant list
- [ ] Verify all executed actions appear in the activity log panel
- [ ] Trigger and cancel a confirmation-gated action — verify no executed action history record is created
- [ ] Inspect runtime action history object — verify sanitized result text and absence of forbidden fields

---

## New Functions

| Function | Visibility | Purpose |
|----------|------------|---------|
| `Get-XdrIncidentEntities` | Private | Extracts entity references from incident/alert evidence |
| `ConvertTo-XdrUserEntity` | Private | Normalizes raw user objects to user entity view model |
| `ConvertTo-XdrDeviceEntity` | Private | Normalizes raw device objects to device entity view model |
| `ConvertTo-XdrFileEntity` | Private | Normalizes raw file objects to file entity view model |
| `Invoke-XdrUserContainment` | Public | Executes user containment actions (revoke sessions, disable) |
| `Invoke-XdrDeviceContainment` | Public | Executes device containment actions (isolate, scan, restrict) |
| `Invoke-XdrFileContainment` | Public | Executes file containment actions (quarantine, block indicator) |
| `Add-XdrActionHistory` | Private | Appends an executed action record to the history list |
