# Phase 7 — Quarantine Review and Response

**Status**: 🟡 In Progress  
**Depends on**: [Phase 2 — Incident and Alert Operations](phase-2-incident-alert-ops.md), [Phase 6 — UX Hardening, Testing, and Docs](phase-6-ux-testing-docs.md)  
**Blocks**: —  
**Last updated**: 2026-05-21

---

## Goals

1. Add a quarantine review workflow for Defender for Office 365 email messages.
2. Support analyst actions for quarantined messages, starting with release and delete.
3. Keep the permission model delegated-only, with no certificate or client secret requirement.
4. Clarify the split between Microsoft Graph delegated permissions for XDR data and Exchange Online delegated access for quarantine operations.

---

## Scope Lock

### Quarantine data source

- Quarantine message review and response uses Exchange Online PowerShell cmdlets, not Microsoft Graph Security incident or alert APIs.
- The current service layer uses:
  - `Get-QuarantineMessage`
  - `Release-QuarantineMessage`
  - `Delete-QuarantineMessage`
- Initial scope is email quarantine only. Non-email quarantine item types are out of scope until validated.

### Permission model

- The project remains delegated-only.
- Incident and alert workflows continue to use delegated Microsoft Graph permissions.
- Quarantine workflows use delegated Exchange Online PowerShell sign-in through `Connect-ExchangeOnline`.
- This is viable without app-only credentials, but authorization is not controlled by Microsoft Graph delegated scopes alone.
- Effective quarantine access must be validated through:
  - user-interactive delegated Exchange Online session authentication
  - the Exchange Online / Defender for Office 365 role assignments granted to that signed-in user
- Least-privilege role mapping for quarantine actions must be confirmed in a test tenant before the dashboard workflow is considered complete.

### UX boundaries

- Phase 7 should not replace existing incident and alert panels.
- Quarantine should become a dedicated workflow area with its own list, details, and actions.
- Destructive actions must remain confirmation-gated.

---

## Tasks

### Workstream 1: Permission and Connection Model

- [x] **1.1** Document the delegated-only authentication split:
  - Microsoft Graph delegated permissions for Defender XDR incident and alert workflows
  - Exchange Online delegated sign-in for quarantine workflows
- [x] **1.2** Define the minimum supported quarantine prerequisites:
  - `ExchangeOnlineManagement` installed
  - `Connect-ExchangeOnline` completed by the signed-in analyst
  - appropriate Exchange Online / Defender for Office 365 role assignments present
- [ ] **1.3** Confirm whether the existing app registration model can be reused directly for quarantine workflows or whether Exchange Online delegated sign-in must be handled as a separate user session
- [ ] **1.4** Record the validated least-privilege role set for:
  - quarantine read/review
  - release to recipients
  - delete from quarantine
- [ ] **1.5** Define degraded behavior when the Exchange Online quarantine session is unavailable or under-privileged

### Workstream 2: Quarantine Service Layer

- [x] **2.1** Add `Get-XdrQuarantineMessage` for normalized quarantine message retrieval
- [x] **2.2** Add `Invoke-XdrQuarantineAction` for release/delete operations
- [x] **2.3** Enforce safe release targeting (`ReleaseToAll` or explicit recipient list)
- [ ] **2.4** Add richer filtering support for sender, recipient, quarantine type, and date range in usage guidance and future UI bindings
- [ ] **2.5** Normalize role/permission errors into analyst-friendly status messages

### Workstream 3: Quarantine TUI Integration

- [ ] **3.1** Add a dedicated quarantine list panel or mode
- [ ] **3.2** Add quarantine details rendering for the selected message
- [ ] **3.3** Add quarantine action entries for release and delete
- [ ] **3.4** Add keyboard shortcuts and contextual help for quarantine navigation
- [ ] **3.5** Ensure disabled reasons are visible when the Exchange Online session or permissions are missing
- [ ] **3.6** Ensure the UI clearly differentiates Graph-backed actions from Exchange Online-backed actions

### Workstream 4: Safety, Testing, and Validation

- [x] **4.1** Add focused Pester coverage for quarantine retrieval and action wrappers
- [ ] **4.2** Add tests for quarantined-message disabled reasons and permission-state rendering once UI integration exists
- [ ] **4.3** Validate confirmation prompts for delete and high-impact release operations
- [ ] **4.4** Run manual test-tenant validation for:
  - review messages
  - release to all
  - release to explicit recipients
  - delete from quarantine
- [ ] **4.5** Confirm auditability expectations for delegated quarantine actions performed by a signed-in analyst

### Workstream 5: Documentation

- [x] **5.1** Add README guidance for quarantine cmdlets and Exchange Online prerequisites
- [x] **5.2** Update README permissions guidance so delegated Exchange Online access is clearly described separately from Graph delegated permissions
- [x] **5.3** Keep the plan index aligned with the quarantine workstream
- [ ] **5.4** Capture validated permission findings after test-tenant verification

---

## Acceptance Criteria

- [ ] A reviewer can identify the supported quarantine API surface and why Graph is not used for these actions
- [ ] The repository documentation clearly states that quarantine uses delegated Exchange Online PowerShell access
- [ ] The repository documentation clearly states that Exchange Online quarantine authorization depends on user sign-in plus Exchange/Defender role assignment validation
- [ ] A dedicated quarantine phase exists in the planning set
- [ ] Test-tenant validation confirms the minimum viable delegated permission model for review, release, and delete

---

## Open Questions

1. Can the current Entra app registration and `ClientId` flow be reused for Exchange Online delegated quarantine workflows, or should quarantine remain a separate `Connect-ExchangeOnline` user session?
2. What is the minimum Exchange Online / Defender for Office 365 role assignment that permits quarantine review only?
3. What additional role assignment is required for release and delete?
4. Should quarantine be a permanent panel in the main dashboard or a separate mode launched from the existing TUI?

---

## Relevant Files

- [README.md](../README.md) — user-facing setup and permission guidance
- [plans/index.md](index.md) — phase index and progress tracker
- [src/Public/Get-XdrQuarantineMessage.ps1](../src/Public/Get-XdrQuarantineMessage.ps1) — quarantine retrieval wrapper
- [src/Public/Invoke-XdrQuarantineAction.ps1](../src/Public/Invoke-XdrQuarantineAction.ps1) — quarantine action wrapper
