---
name: pwshxdrspectre-spectre-layout
description: 'Spectre.Console layout construction and mutation rules for the PwshXDRSpectre live dashboard. Use when adding or rearranging Spectre Layout rows/columns, swapping the dashboard frame panel, sizing panels by ratio or absolute width, computing dynamic column widths from console size, choosing border colors and styles, rendering panel headers with markup, or wiring outer tabs and the action panel into the screen layout. Covers slot-vs-logical-panel naming, Panel child-data immutability, layout rebuild flow via Update-XdrLiveOuterTabs, deepskyblue1/orange1 theme conventions, action panel label shortening, and dynamic title trimming with ellipsis.'
---

# PwshXDRSpectre Spectre Layout Building

Repo-specific rules for assembling and mutating Spectre.Console layouts in the live dashboard. Generic Spectre API docs are not repeated; this captures only what reliably trips us up.

## When to Use This Skill

- Editing `New-XdrLiveDashboardLayout.ps1` or anything it composes
- Adding a new panel/tab/slot to the dashboard
- Resizing or re-ratio'ing the incident/alert/preview/action columns
- Changing border colors, header markup, or active-tab styling
- Toggling action panel visibility and reflowing the surrounding columns
- Computing column widths inside `Start-PwshXdrLiveDashboard.ps1`'s render loop

## Layout Slots vs Logical Panels

Two parallel naming schemes — keep them straight:

- **Physical slot ids** (Spectre `Layout` names): `left_top`, `center_top`, `right_actions`, etc. Used to address the layout tree (`$layout["left_top"].Update(...)`).
- **Logical panel ids** (workflow focus): `incident_list`, `alert_list`, `incident_details`, `query_catalog`, `query_result`, `entity_list`, etc. Used by help text, keyboard routing, diagnostics, and tab activation.

Help text, shortcut routing, and the active-panel border highlight key off the **logical** id. Slot-only refactors must not change the logical id, or every keyboard handler downstream breaks silently.

## Panels Are Effectively Immutable

`Spectre.Console.Panel` does not expose a mutable child-data property. You cannot swap a panel's contents in place; you replace the panel.

Standard mutation flow for shape changes (action panel toggle, layout switch, tab swap that reshapes the dashboard frame):

1. Rebuild the affected subtree by calling `New-XdrLiveDashboardLayout` (or a sub-builder) with the new shape.
2. Replace the dashboard frame panel reference held by the runtime context.
3. Call `Update-XdrLiveOuterTabs` to reattach the rebuilt frame to the screen layout — otherwise the old panel stays painted.

In-place text/data updates inside an existing panel still go through `$layout["<slot>"].Update($newPanel)` with a freshly constructed `Panel`, not by mutating the previous instance.

## Sizing & Ratios

- The outer dashboard splits into columns by `Ratio`. The action panel toggle changes the **ratios in the row containing it**, not just its visibility — recompute downstream column widths whenever it toggles.
- For width-aware text tables (incident list, alert list), derive width from `[Console]::WindowWidth` (with `$Host.UI.RawUI.WindowSize.Width` as fallback) and the current ratio share, then subtract panel chrome (~6 chars).
- Pattern used in `Start-PwshXdrLiveDashboard.ps1`:

  ```powershell
  $consoleWidth        = try { [Console]::WindowWidth } catch { $Host.UI.RawUI.WindowSize.Width }
  $incidentListRatio   = if ($actionPanelVisible) { 2 } else { 1 }
  $totalRatio          = if ($actionPanelVisible) { 7 } else { 2 }
  $panelWidth          = [Math]::Max(20, [int][Math]::Floor(($consoleWidth * $incidentListRatio) / $totalRatio) - 6)
  ```

- **Fixed columns** (incident list): `Sev = 3`, `ID = 2`, `Status = 6`. Title takes the remainder: `Math.Max(8, $panelWidth - 3 - 2 - 6 - 3)`.
- **Fixed columns** (alert list): `Sev = 3`, `Status = 6`. Title gets the rest: `Math.Max(8, $panelWidth - 3 - 6 - 2)`.
- Always trim oversize titles with `...` before rendering. Static title widths cause wrapping when the action panel toggles or the terminal narrows.

## Theme & Markup Conventions

- **Border accent**: `deepskyblue1` for inactive borders, `orange1` for the active/focused panel border.
- **Outer tabs** (`Get-XdrLiveOuterTabsHeader`): inactive `[deepskyblue1 on #1C1C1C]| label |[/]`, active `[bold black on orange1]| label |[/]`. Tabs are pure markup — do not add `Panel` chrome around them.
- **Panel header markup** is built in `Get-PanelHeaderMarkup`, border style/color in `Get-PanelBorderStyle` / `Get-PanelBorderColor`. Funnel new panels through these helpers so the theme stays consistent.
- **Action panel labels**: shorten only the *rendered/entry* label ("Set Inc. to Active", "Assign Inc. to me", "(Alt+Shift+L) Reload alerts"). The verbose action name passed to `Get-XdrActionDisableReasons -ActionName "Set incident status to Active"` (and friends) must stay verbose so policy/safety lookups continue to match.

## Rendering Inside the Loop

- Build `Panel` instances each tick from current state; do not cache the `Panel` itself across ticks.
- `Spectre.Console.Markup` strings are pre-escaped in this repo via `Get-SpectreEscapedText` / `ConvertTo-SafeSpectreText` / `ConvertTo-SafePanelData`. Always run user/Graph-derived text through one of these before composing markup, or a single `[` in an alert title will break rendering.
- The render loop is throttled at the **top** of `while ($true)`. Skipping render must not skip the throttle. Layout reshapes happen before render, never after.

## Common Pitfalls

| Symptom | Cause |
|---|---|
| Old panel still on screen after a layout rebuild | Forgot to call `Update-XdrLiveOuterTabs` to reattach the new frame. |
| Title text wraps to a second line when action panel opens | Static title width; recompute from `$consoleWidth` + current ratio share. |
| Active panel border looks the same as inactive | Border color not routed through `Get-PanelBorderColor` for the focused logical id. |
| Tab colors clash with dashboard borders | Markup hard-coded outside `Get-XdrLiveOuterTabsHeader`, or active/inactive colors swapped. |
| `Set incident status to Active` policy check stops disabling the button | Someone shortened the `-ActionName` argument too. Keep policy strings verbose; only shorten display labels. |
| Spectre throws "Markup not closed" mid-render | Unescaped `[` in Graph-derived text. Route it through `ConvertTo-SafeSpectreText`. |
| Help text or shortcuts target the wrong panel after a slot rename | Logical panel id was changed alongside the slot id. Revert the logical id; only the slot moved. |