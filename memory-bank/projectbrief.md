# Project Brief

## Project
PwshXDRSpectre is a PowerShell module that provides a terminal UI for Microsoft Defender XDR using PwshSpectreConsole.

## Goals
- Give analysts a live dashboard for incident and alert triage.
- Support containment workflows for users, devices, and files.
- Support context-aware hunting queries loaded from repository JSON files.
- Evolve toward persistent workflow memory and agent-style operations.

## Scope
- Module-first PowerShell implementation under `src/`.
- Public entry points with private helper scripts and a shared runtime context.
- Single active tenant for v1.
- Microsoft Graph cmdlets plus direct Graph REST when cmdlets are insufficient.
- Repository-backed hunting query catalog under `queries/`.
- Local append-only memory store is planned but not yet implemented.

## Non-Goals
- Backwards compatibility with earlier internal dashboard shapes is not required.
- Multi-tenant orchestration is not part of v1.

## Success Criteria
- Dashboard remains responsive while loading incidents, alerts, entities, and hunting results.
- Triage and safety-policy workflows behave predictably in the TUI.
- Query execution is asynchronous, cached by stable context, and visible in the activity UI.
- Pester coverage protects core runtime, helper, and workflow contracts.
