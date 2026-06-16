# Product Context

## Why This Exists
Security analysts need a keyboard-driven terminal workflow for Microsoft Defender XDR that avoids repeatedly pivoting through multiple web experiences for triage, investigation, and follow-up actions.

## Problems It Solves
- Slow context switching between incidents, alerts, entities, and hunting workflows.
- Repetitive lookup and enrichment work during triage.
- Need for fast, scriptable analyst workflows in PowerShell-centric environments.
- Need for explicit safety controls around high-impact actions.

## User Experience Goals
- Fast startup and responsive navigation in the live dashboard.
- Clear panel structure with stable keyboard shortcuts.
- Non-blocking background loading for Graph and hunting operations.
- Safety policy feedback that explains why an action is disabled.
- Predictable transitions between top-level workflows such as Incidents and Hunting.

## Current Product Shape
- Main live entry point: `Start-PwshXdrLiveDashboard`.
- Query library is loaded from repository JSON files at startup.
- Hunting mode runs inside the existing dashboard shell rather than a separate app.
- Placeholder top-level tabs exist for future workflows such as Quarantine, Action Center, and Settings.
