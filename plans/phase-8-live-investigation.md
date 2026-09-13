# Phase 8 — Device Live Investigation

## Goal

Add a global **Live Investigation** dashboard workspace for Microsoft Defender for Endpoint devices and expose a small terminal-safe core for starting confirmed Live Response commands.

## Scope

- Reuse the existing authenticated runtime context and operation-result contract.
- Query onboarded devices from the Defender machine inventory endpoint.
- Start Live Response commands only after capability checks and PowerShell confirmation.
- Surface the workflow as a global navigation tab without changing incident triage behavior.
- Treat the `.references/XDRInternals` implementation as design input when it is available; keep this module's runtime dependency-free implementation in `src/Public`.

## Tasks

- [x] Add public device inventory cmdlet: `Get-XdrLiveInvestigationDevice`.
- [x] Add public Live Response starter cmdlet: `Start-XdrLiveInvestigation`.
- [x] Register live investigation device capabilities after a successful session connection.
- [x] Add the global Live Investigation tab, tab label, panel order, and placeholder panel copy.
- [x] Add focused Pester coverage for request payloads, capability fail-closed behavior, and tab wiring.
- [ ] Add machine-action polling and command history panels.
- [ ] Load device search results directly inside the TUI.
- [ ] Add guarded interactive command builders for common response actions.
- [ ] Reconcile any reusable XDRInternals helpers if the reference submodule is present in future clones.

## Safety and Permissions

- Live Response is high impact; command submission uses `SupportsShouldProcess` with `ConfirmImpact = High`.
- Device actions fail closed unless the runtime context exposes `GetLiveInvestigationDevices` or `StartLiveInvestigation`.
- API permission failures should be reflected through the existing operation/error envelope and permission-health downgrade path.

## Relevant Files

- [src/Public/Get-XdrLiveInvestigationDevice.ps1](../src/Public/Get-XdrLiveInvestigationDevice.ps1)
- [src/Public/Start-XdrLiveInvestigation.ps1](../src/Public/Start-XdrLiveInvestigation.ps1)
- [src/Public/Start-PwshXdrLiveDashboard.ps1](../src/Public/Start-PwshXdrLiveDashboard.ps1)
- [src/Private/Show-XdrLiveNonIncidentTab.ps1](../src/Private/Show-XdrLiveNonIncidentTab.ps1)
- [src/Private/Get-XdrLivePanelOrder.ps1](../src/Private/Get-XdrLivePanelOrder.ps1)
- [src/Private/Get-XdrLiveOuterTabsHeader.ps1](../src/Private/Get-XdrLiveOuterTabsHeader.ps1)
