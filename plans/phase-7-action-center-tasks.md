# Phase 7 — Action Center Tasks

**Status**: ⚪ Research Complete, Not Started  
**Depends on**: [Phase 2 — Incident and Alert Operations](phase-2-incident-alert-ops.md), [Phase 3 — Entity Pivots and Containment Actions](phase-3-entity-containment.md), [Phase 5 — Agent Workflow Memory Store](phase-5-workflow-memory.md)  
**Can overlap**: Late Phase 3 and Phase 6  
**Blocks**: —  
**Last updated**: 2026-05-25

---

## Goals

1. Add an Action Center mode focused on remediation tasks that require analyst attention.
2. Surface Action Center history and pending task context in the TUI without relying on portal-only scraping.
3. Support safe interactions for any action type with a documented, supported API.
4. Keep approval, rejection, undo, and cancellation operations permission-aware and confirmation-gated.
5. Record Action Center task decisions in the same redaction-ready action history model used by Phase 5.

---

## API Research Findings

### Confirmed supported API surface

Microsoft documents the unified Action center as the portal experience for viewing pending and completed remediation actions across devices, email content, and identities. The portal documentation covers the **Pending** and **History** tabs, required roles, approval, rejection, and undo workflows, but it does not document a public unified Action center REST API for listing, approving, or rejecting every task type.

The currently documented API surface that maps directly to part of Action Center history is Microsoft Defender for Endpoint **machineActions**:

- [List MachineActions API](https://learn.microsoft.com/defender-endpoint/api/get-machineactions-collection)
  retrieves MDE machine actions and supports OData filters on `id`, `status`, `machineId`, `type`, `requestor`, and `creationDateTimeUtc`.
- [Get machineAction API](https://learn.microsoft.com/defender-endpoint/api/get-machineaction-object)
  retrieves one machine action by ID.
- [Cancel machine action API](https://learn.microsoft.com/defender-endpoint/api/cancel-machine-action)
  cancels a launched machine action that is not in a final state.
- [machineAction resource type](https://learn.microsoft.com/defender-endpoint/api/machineaction)
  defines action types such as `RunAntiVirusScan`, `CollectInvestigationPackage`, `Isolate`, `Unisolate`, `StopAndQuarantineFile`, `RestrictCodeExecution`, and `UnrestrictCodeExecution`.

These APIs are not Microsoft Graph Security cmdlets. They are Defender for Endpoint REST endpoints under `https://api.security.microsoft.com/api`.

### Portal-only or unconfirmed surface

The following workflows are documented as Microsoft Defender portal workflows, but this research did not find a supported public API for the unified Action center approval queue:

- Approving or rejecting unified Action center pending actions across all workloads.
- Undoing unified Action center history entries across all workloads.
- Approving Defender for Office 365 AIR pending actions from the unified Action center.
- Listing a normalized unified Action center task model that includes device, email, identity, advanced hunting, Explorer, and live response actions.

Do not implement these workflows by scraping the Defender portal or calling private browser endpoints. The first implementation should fail closed and expose these operations as unsupported until a documented API is identified.

### Permission considerations

Action Center task permissions are broader than the current Graph incident scopes:

- Existing incident and alert operations use delegated Microsoft Graph security permissions such as `SecurityIncident.ReadWrite.All`.
- MDE machineActions use Defender for Endpoint API permissions such as delegated `Machine.ReadWrite` for read/list/get and action-specific permissions for cancellation or mutation.
- Defender portal Action Center tasks also depend on tenant roles, Unified RBAC, Defender for Endpoint roles, and for Office content the Search and Purge role.

Phase 7 must extend permission-health checks rather than treating Graph incident write scope as sufficient.

### Recommended scope decision

Implement Phase 7 in two stages:

1. **Stage A: Supported read-first Action Center mode**
   - Use MDE machineActions to provide Action Center history and in-progress action visibility for device actions.
   - Add filters by status, device, action type, requestor, and time window.
   - Support cancellation only for machine actions that are not in a final state.
2. **Stage B: Approval workflow abstraction**
   - Define a provider interface for pending task queues.
   - Keep unified approve/reject providers disabled until a documented API exists.
   - Add provider stubs for Office 365 AIR, identity tasks, and unified Action center tasks that return a clear unsupported reason.

---

## Tasks

### Workstream 1: Action Center Provider Model

- [ ] **1.1** Define an Action Center task view model with the following fields:
  - `TaskId`
  - `Provider`
  - `Source`
  - `ActionType`
  - `Status`
  - `TargetType`
  - `TargetId`
  - `TargetName`
  - `Requestor`
  - `CreatedAt`
  - `LastUpdatedAt`
  - `CanApprove`
  - `CanReject`
  - `CanCancel`
  - `CanUndo`
  - `UnsupportedReason`
  - `RawObject`
- [ ] **1.2** Define provider names:
  - `MdeMachineActions`
  - `UnifiedActionCenter`
  - `OfficeAir`
  - `IdentityActions`
- [ ] **1.3** Implement provider capability metadata so unsupported providers can explain why a workflow is unavailable.
- [ ] **1.4** Add `Context.Data.ActionCenterTasks` and `Context.Selection.ActionCenterTask` to the runtime context.
- [ ] **1.5** Add `Context.Capabilities.ActionCenterActions` for available operations based on provider, task status, and permissions.

### Workstream 2: MDE Machine Action Reader

- [ ] **2.1** Implement `Public/Get-XdrActionCenterTasks.ps1` with a provider parameter that defaults to supported providers only.
- [ ] **2.2** Implement `Private/Get-XdrMdeMachineActions.ps1` to call `GET https://api.security.microsoft.com/api/machineactions`.
- [ ] **2.3** Support filters for:
  - `Status`
  - `MachineId`
  - `ActionType`
  - `Requestor`
  - `CreatedAfter`
  - `CreatedBefore`
  - `Top`
  - `Skip`
- [ ] **2.4** Normalize machineAction responses to the Action Center task view model.
- [ ] **2.5** Treat final MDE statuses (`Succeeded`, `Failed`, `TimeOut`, `Cancelled`) as not cancellable.
- [ ] **2.6** Surface API throttling and permission failures through `Invoke-XdrOperation` with non-terminating error contracts.
- [ ] **2.7** Add endpoint URL selection for global and sovereign Defender API roots as configuration, not hardcoded branching.

### Workstream 3: Cancellation Workflow

- [ ] **3.1** Implement `Public/Invoke-XdrActionCenterTaskAction.ps1` with an initial supported action of `Cancel`.
- [ ] **3.2** Implement `Private/Invoke-XdrMdeMachineActionCancel.ps1` to call `POST /api/machineactions/{id}/cancel`.
- [ ] **3.3** Require a confirmation prompt before cancellation.
- [ ] **3.4** Require a cancellation comment and store only a sanitized summary in action history.
- [ ] **3.5** Reject cancellation locally when the task is already in a final state.
- [ ] **3.6** Refresh the selected task after cancellation so the TUI reflects the updated status.

### Workstream 4: Unsupported Approval and Undo Providers

- [ ] **4.1** Implement `Private/Get-XdrUnsupportedActionCenterProvider.ps1` for unified, Office AIR, and identity providers.
- [ ] **4.2** Unsupported providers must return structured task capability records with:
  - `Provider`
  - `IsSupported = $false`
  - `UnsupportedReason`
  - `DocumentationLink`
- [ ] **4.3** The TUI must show unsupported providers in a Help or Capability panel, not as executable actions.
- [ ] **4.4** Attempting `Approve`, `Reject`, or `Undo` without a supported provider must fail closed before any network call.
- [ ] **4.5** Add a research follow-up item to revisit unified Action center API availability before enabling approval workflows.

### Workstream 5: TUI Mode and Navigation

- [ ] **5.1** Add an Action Center mode entry point or dashboard panel switch that reuses the existing live dashboard shell.
- [ ] **5.2** Add an Action Center task list panel with columns:
  - `Status`
  - `ActionType`
  - `TargetName`
  - `Requestor`
  - `CreatedAt`
  - `Provider`
- [ ] **5.3** Add a task details panel showing requestor comment, related file info, machine name, and unsupported reason.
- [ ] **5.4** Add keyboard actions:
  - `Alt+C` — cancel selected cancellable task
  - `F5` or `r` — refresh tasks
  - `F1` — show Action Center help
- [ ] **5.5** Add filter controls for pending, in-progress, final, and failed actions.
- [ ] **5.6** Preserve incident, alert, and entity selections when switching between dashboard and Action Center mode.
- [ ] **5.7** Show provider capability warnings in the existing disabled-reasons panel pattern.

### Workstream 6: Permissions and Configuration

- [ ] **6.1** Extend permission-health schema with an `ActionCenter` section.
- [ ] **6.2** Validate the current token can call Defender for Endpoint REST APIs before enabling MDE machine action reads.
- [ ] **6.3** Add configuration for Defender API root:
  - Default: `https://api.security.microsoft.com`
  - Sovereign cloud override: configurable value
- [ ] **6.4** Add permission guidance for:
  - MDE machine action reads
  - MDE cancellation and action-specific permissions
  - Defender portal Action Center roles
  - Office Search and Purge role requirements
- [ ] **6.5** Ensure missing Action Center permissions do not downgrade unrelated incident and alert actions.

### Workstream 7: Action History and Audit Trail

- [ ] **7.1** Extend the Phase 5 action-history schema with Action Center fields:
  - `Provider`
  - `TaskId`
  - `TaskStatusBefore`
  - `TaskStatusAfter`
  - `ActionCenterOperation`
- [ ] **7.2** Record successful cancellations as action history entries.
- [ ] **7.3** Record failed or unsupported attempts as diagnostics, not executed action records.
- [ ] **7.4** Redact comments and raw API payloads before adding records to in-memory or persisted history.
- [ ] **7.5** Add correlation back to selected incident, alert, device, or file when available.

### Workstream 8: Tests

- [ ] **8.1** `Tests/Get-XdrActionCenterTasks.Tests.ps1` — returns normalized MDE machine action tasks.
- [ ] **8.2** `Tests/Get-XdrMdeMachineActions.Tests.ps1` — builds OData filters correctly and handles paging parameters.
- [ ] **8.3** `Tests/ConvertTo-XdrActionCenterTask.Tests.ps1` — maps all required task view-model fields.
- [ ] **8.4** `Tests/Invoke-XdrActionCenterTaskAction.Tests.ps1` — rejects unsupported `Approve`, `Reject`, and `Undo` actions without network calls.
- [ ] **8.5** `Tests/Invoke-XdrMdeMachineActionCancel.Tests.ps1` — posts the cancellation payload only for cancellable states.
- [ ] **8.6** `Tests/Get-XdrUnsupportedActionCenterProvider.Tests.ps1` — returns clear unsupported reasons and documentation links.
- [ ] **8.7** `Tests/Start-PwshXdrLiveDashboard.Tests.ps1` — verifies UI code calls services only and does not call Defender REST endpoints directly.
- [ ] **8.8** Permission-health tests cover Action Center permission failures without disabling unrelated incident and alert capabilities.

---

## Acceptance Criteria

- [ ] Action Center mode lists supported MDE machine action tasks from the documented MDE API.
- [ ] Analysts can filter Action Center task history by status, action type, requestor, target device, and time window.
- [ ] Cancellation is available only for non-final MDE machine actions and always requires confirmation.
- [ ] Unified approve, reject, and undo workflows fail closed with a clear unsupported message until documented APIs are available.
- [ ] The UI never scrapes Defender portal pages or calls private portal endpoints.
- [ ] Action Center permissions are tracked separately from incident and alert Graph permissions.
- [ ] Supported Action Center task operations are recorded in redaction-ready action history.
- [ ] TUI code does not call REST APIs directly; service functions own all network calls.

---

## Manual Validation Checklist

- [ ] Connect with a tenant that has Defender for Endpoint permissions.
- [ ] Load Action Center mode and verify MDE machine actions appear.
- [ ] Filter tasks to `Pending` or `InProgress` and verify only matching actions are shown.
- [ ] Select a final-state task and verify cancellation is disabled with a clear reason.
- [ ] Select a non-final test machine action, cancel with a comment, and verify the MDE action status updates.
- [ ] Attempt `Approve`, `Reject`, or `Undo` and verify the module fails closed before any network call.
- [ ] Verify missing MDE permissions show an Action Center warning without breaking incident and alert triage.
- [ ] Inspect action history and verify cancellation records contain no raw API payloads or sensitive comments.

---

## Security Notes

- Do not scrape the Defender portal or rely on private browser network endpoints.
- Treat all Action Center comments as analyst-provided input; sanitize before display and persistence.
- Keep cancellation, approval, rejection, and undo operations confirmation-gated.
- Fail closed when provider support or permissions are ambiguous.
- Respect MDE API rate limits by throttling refreshes and avoiding polling loops faster than documented limits.
- Keep Defender API root configuration explicit so sovereign cloud support does not require code changes.

---

## New Functions

| Function | Visibility | Purpose |
|----------|------------|---------|
| `Get-XdrActionCenterTasks` | Public | Lists supported Action Center task providers and returns normalized task view models |
| `Invoke-XdrActionCenterTaskAction` | Public | Executes supported task operations such as MDE machine action cancellation |
| `Get-XdrMdeMachineActions` | Private | Calls the documented MDE machineActions list API |
| `ConvertTo-XdrActionCenterTask` | Private | Normalizes provider-specific action objects to the task view model |
| `Invoke-XdrMdeMachineActionCancel` | Private | Cancels an MDE machine action that is not in a final state |
| `Get-XdrUnsupportedActionCenterProvider` | Private | Returns structured unsupported-provider capability details |
