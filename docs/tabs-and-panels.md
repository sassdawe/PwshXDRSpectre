# Dashboard Tabs and Panels

The live dashboard uses one compact tab strip as the title of the outer dashboard frame. The tab strip changes workflow mode. The screen positions stay stable, but each workflow now has its own logical panel names.

## Top-Level Tabs

| Tab | Shortcut | Purpose | Current behavior |
| --- | --- | --- | --- |
| Welcome | `Alt+1` | Entry and orientation page | Shows welcome/session information and no workflow actions. |
| Incidents | `Alt+2` | Main incident and alert workflow | Shows incident list, details or entities, alerts, alert details, and incident or alert actions. |
| Hunting | `Alt+3` or `Alt+H` | Query catalog, preview, execution, and results | Shows dedicated query catalog, preview, activity, results, and query action panels. |
| Query Library | `Alt+4` | Saved query management | Placeholder panels for query metadata, versions, preview, and future actions. |
| Quarantine | `Alt+5` | Future quarantine workflow | Placeholder panels marked under construction. |
| Action Center | `Alt+6` | Future action review workflow | Placeholder panels marked under construction. |
| Settings | `Alt+7` | Runtime settings and diagnostics | Shows input debug state, log path, theme color, and log placeholders. |
| Help | `Alt+8` | Keyboard and workflow help | Shows context-aware help content and support placeholders. |

`Alt+H` toggles between the Incidents and Hunting workflows. Entering Hunting from a selected entity keeps that entity in context so query parameter binding can use values such as `UserId`, `DeviceId`, or `FileHash`.

## Physical Layout Slots

The dashboard has one outer `dashboard_frame` panel. Its header contains the tab strip. Inside the frame, the `root` layout has a main work area and a persistent help row.

These names are physical screen slots only. They are not workflow semantics.

| Slot ID | Position | Physical role |
| --- | --- | --- |
| `left_top` | Upper-left | Primary list for the active workflow. |
| `left_bottom` | Lower-left | Secondary list or activity stream. |
| `center_top` | Upper-center | Details, preview, or entity list. |
| `center_bottom` | Lower-center | Selected item details or results. |
| `right_actions` | Full-height right side | Actions, disabled reasons, status, and modal wizards. |
| `help` | Full-width bottom row | Context-aware shortcuts, status, heartbeat, and diagnostics. |

Logical panel names are mapped onto these slots by `Resolve-XdrLivePanelSlot`. This keeps keyboard routing and help text tied to workflow meaning instead of reusing an `incidents` panel to mean both incident rows and hunting queries.

## Incidents Workflow Panels

| Logical panel | Slot | Title in Incidents workflow | What it shows |
| --- | --- | --- | --- |
| `incident_list` | `left_top` | Incident List | Incident rows with severity, incident ID, title, and status. |
| `incident_details` | `center_top` | Incident details or Entities | Either incident JSON details or incident-linked entities. `Alt+E`, `Alt+D`, or `Tab` switches between those views when this panel is active. |
| `alert_list` | `left_bottom` | Alert List | Alerts for the selected incident. Alerts load explicitly through `Enter`, `Alt+L`, or `Alt+Shift+L`. |
| `alert_details` | `center_bottom` | Alert Details | Details for the selected alert. |
| `incident_actions` | `right_actions` | Action Status or wizard title | Incident and alert actions, disabled-state reasons, or active modal workflows such as resolve, classify, and comment. |
| `help` | `help` | Help | Context-aware shortcuts and live diagnostics such as heartbeat and input debug state. |

The incident focus order is:

1. `incident_list`
2. `incident_details`
3. `alert_list`
4. `incident_actions`

The `alert_details` panel is informational and is not currently part of the focus order.

Alert and entity data are cached by incident ID. When selection changes, the dashboard restores cached alerts and entities for the selected incident instead of loading them automatically.

## Alert Loading and Cache Diagnostics

Incident list loading stays lightweight on purpose. `Get-XdrIncidents` does not expand alert references for every incident because that can slow startup and make the live dashboard less responsive. Alerts are loaded through the dedicated alert path when the analyst presses `Enter`, `Alt+L`, or `Alt+Shift+L`.

`Get-XdrAlerts` handles incidents from the lightweight list. If the selected incident does not already include `AlertRefs` or `Alerts`, it fetches that one incident with `-ExpandProperty 'alerts'`, then retrieves each referenced alert with `Get-MgSecurityAlertV2`. This keeps startup fast while still allowing explicit alert loading to populate the Alert List.

The dashboard log records each important step in the cache path:

- `Alert preload job completed` includes the incident ID, result status, alert count, and result message from the background alert job.
- `Alert cache restore miss` means no cache entry exists yet for the selected incident.
- `Alert cache restore hit` means a cache entry exists and shows how many alerts were restored into context.
- `Alert cache restore completed with empty alert list` means the cache entry exists but contains zero alerts.
- `Alert cache restore selected alert` means the restore picked a concrete alert and selected index.

If alerts do not appear, check the log in this order:

1. Confirm an `Alert preload job completed` entry exists for the selected incident.
2. Check the `AlertCount` on that preload completion entry.
3. If `AlertCount=0`, inspect the `Message` field. A successful empty result usually means Graph returned no alert references for that incident, or the incident reference expansion path did not run.
4. If the preload entry has alerts but the restore entry is empty, investigate `Invoke-XdrLiveAlertLoadJobProcessing` and `Restore-XdrLiveCachedAlertsForIncident`.

When temporarily turning off alert preloading, lazy alert expansion, entity extraction, or any other background workflow for debugging, document both sides of the change in the same pull request or commit notes: what was disabled, why it was disabled, and the exact function or condition to restore when debugging is done.

## Hunting Workflow Panels

| Logical panel | Slot | Title in Hunting workflow | What it shows |
| --- | --- | --- | --- |
| `query_catalog` | `left_top` | Query Catalog | Query definitions loaded from the repository `queries/` folder. |
| `query_preview` | `center_top` | Query Preview | Selected query name, description, required context, and interpolated KQL preview. |
| `query_activity` | `left_bottom` | Activity Log | Recent query runs and execution status. |
| `query_results` | `center_bottom` | Query Results | Rows from the selected query's latest cached result. |
| `query_actions` | `right_actions` | Query Actions | Execute selected query, return to incident workflow, blocked-state reasons, and selected entity context. |
| `help` | `help` | Help | Hunting-specific shortcuts and input diagnostics. |

The hunting focus order is:

1. `query_catalog`
2. `query_preview`
3. `query_activity`
4. `query_actions`

The `query_results` panel is informational and is not currently part of the focus order.

Hunting query execution runs in a background job. The live loop folds completed results back into the panel state so keyboard input and rendering stay responsive.

## Placeholder Tabs

The Welcome, Query Library, Quarantine, Action Center, Settings, and Help tabs render through the same physical slots, but each tab uses tab-specific logical panel names. These tabs are mostly placeholders today, but they still keep the live loop active. Incident loading, alert preload jobs, query jobs, and help refreshes continue while those tabs are selected.

| Tab | `left_top` | `center_top` | `left_bottom` | `center_bottom` | `right_actions` |
| --- | --- | --- | --- | --- | --- |
| Welcome | `welcome_overview` | `welcome_info` | `welcome_announcements` | `welcome_session` | `welcome_actions` |
| Query Library | `query_library_list` | `query_library_settings` | `query_library_versions` | `query_library_preview` | `query_library_actions` |
| Quarantine | `quarantine_items` | `quarantine_status` | `quarantine_info` | `quarantine_details` | `quarantine_actions` |
| Action Center | `action_center_items` | `action_center_status` | `action_center_info` | `action_center_details` | `action_center_actions` |
| Settings | `settings_overview` | `settings_debug` | `settings_logs` | `settings_files` | `settings_actions` |
| Help | `help_topics` | `help_tips` | `help_faq` | `help_support` | `help_actions` |

## Design Notes

- The tab strip is not a separate layout row. It is the header of the outer `dashboard_frame` panel, which keeps vertical space available for analyst work.
- Physical slot IDs stay stable while logical panel IDs describe the workflow meaning.
- The Incidents and Hunting tabs are the two full workflow tabs. Other tabs use placeholder content until their workflows are implemented.
- The help panel is rebuilt on every loop iteration so it reflects the current tab, focus panel, modal state, background jobs, and diagnostics.
- Modal incident workflows pin focus to `incident_actions` until they complete or are canceled.
