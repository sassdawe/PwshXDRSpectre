# Phase 4 — Hunting Query Engine from JSON

**Status**: 🟡 In Progress  
**Depends on**: [Phase 1 — Foundation](phase-1-foundation.md)  
**Can overlap**: Late Phase 3  
**Blocks**: Phase 5 (query run metadata)  
**Last updated**: 2026-05-23

---

## Goals

1. Define a repository-based query catalog folder with a JSON schema for KQL hunting queries.
2. Load and validate the catalog at startup with actionable parse errors.
3. Inject selected incident/device/user context into query parameters safely.
4. Provide a TUI flow for query selection, preview, execution, result navigation, and entity pivot-back.
5. Record query run metadata in workflow memory.

## Panel Display Strategy

Phase 4 query UX will reuse the existing three-column live dashboard instead of adding a second permanent row or a separate full-screen view.

- The dashboard will keep the current fixed shell: left list column, center details column, right action/status column, plus header and help.
- Query surfaces are planned as logical panes inside that shell, not as always-visible extra panes.
- The left list column will switch between the normal incident/alert lists and a query-oriented stack when the user enters hunting mode.
- The center details column will switch between incident/alert details and query preview or query results, depending on the active hunting step.
- The right column will remain the command/action area and will show query actions, blocked-state messaging, and recent run status when hunting mode is active.
- Returning to the default incident workflow restores the normal incident, alert, and details content without rebuilding the outer layout.

This means the query catalog, query preview, and query results are expected to be shown and hidden by mode, not rendered as permanently visible additional panels.

---

## Tasks

### Workstream 1: Query Catalog Schema and Folder

- [x] **1.1** Create `queries/` folder as the catalog root
- [x] **1.2** Define the query JSON schema with the following fields:
  - `id` — unique identifier (slug format, e.g., `user-signin-anomalies`)
  - `name` — display name shown in query picker
  - `description` — one-line purpose summary
  - `requiredContext` — array of required context keys (`IncidentId`, `DeviceId`, `UserId`, `FileHash`)
  - `parameters` — array of parameter objects: `{ name, contextBinding, defaultValue, description }`
  - `kql` — the KQL query text with `{{paramName}}` placeholders
  - `displayColumns` — ordered list of result columns to surface in the TUI
  - `tags` — optional array of categorization tags (e.g., `identity`, `device`, `lateral-movement`)
- [x] **1.3** Add 2–3 starter queries as examples:
  - `user-signin-anomalies.json` — sign-in risk events for a selected user
  - `device-process-tree.json` — process execution tree on a selected device
  - `incident-related-alerts.json` — all alerts correlated to a selected incident

### Workstream 2: Startup Loader and Validation

- [x] **2.1** Implement `Private/Get-XdrQueryCatalog.ps1` — scans the `queries/` folder, reads all `.json` files, and returns parsed query objects
- [x] **2.2** Implement `Private/Test-XdrQuerySchema.ps1` — validates each query object against the schema with descriptive errors
  - Required fields must exist
  - `id` must be unique across the catalog
  - `requiredContext` values must be from the allowed context key set
  - `parameters` must reference valid context bindings or have a `defaultValue`
  - `{{paramName}}` placeholders in `kql` must each have a matching parameter definition
- [x] **2.3** Call `Get-XdrQueryCatalog` during startup and populate `Context.Data.QueryCatalog`
- [x] **2.4** Surface schema validation errors in the status panel with the failing file name and reason — do not silently skip invalid queries

### Workstream 3: Context Binding and Parameter Injection

- [x] **3.1** Implement `Private/Resolve-XdrQueryParameters.ps1` — resolves all parameters for a query by reading bound values from the current context
- [ ] **3.2** Context binding rules:
  - `IncidentId` → `Context.Selection.Incident.IncidentId`
  - `DeviceId` → `Context.Selection.Entity.DeviceId` (when a device entity is selected)
  - `UserId` → `Context.Selection.Entity.UserId` (when a user entity is selected)
  - `FileHash` → `Context.Selection.Entity.Sha256` (when a file entity is selected)
- [x] **3.3** Unresolved required context bindings must surface as a blocked state with the missing key listed
- [x] **3.4** Implement `Private/Invoke-XdrQueryInterpolation.ps1` — substitutes resolved parameter values into `{{paramName}}` placeholders in the KQL text
- [x] **3.5** Sanitize interpolated values to prevent KQL injection — allowlist expected formats per binding type (GUID for IDs, alphanumeric for hashes, etc.)

### Workstream 4: TUI Query Flow

- [x] **4.1** Add a Query Catalog panel listing available queries filtered by current context compatibility
- [x] **4.2** Show query name, description, tags, and which required context is satisfied vs. missing
- [x] **4.3** Add a Query Preview panel showing the interpolated KQL text before execution
- [x] **4.4** Implement `Public/Invoke-XdrHuntingQuery.ps1` — submits the interpolated KQL to the Microsoft Defender Advanced Hunting API and returns results
- [ ] **4.5** Add a Query Results panel:
  - Display results in a scrollable table using `displayColumns` from the query definition
  - Show row count and execution time
  - Allow navigation through result rows
- [ ] **4.6** Add pivot-back action from result rows to entity context (select a device/user/file from results to update `Context.Selection.Entity`)
- [x] **4.7** Show a blocked state with clear messaging when required context is missing for a selected query

**Planned interaction model:**

- Default mode keeps the current incident-first dashboard visible.
- Entering hunting mode swaps the visible content of existing panes rather than opening brand new always-on panes.
- Query Catalog and Query Results are therefore workflow states inside the current layout, not extra permanent columns or rows.
- Blocked queries remain selectable in the catalog view but their preview/action area will show the missing context keys instead of enabling execution.

### Workstream 5: Query Run Metadata

- [ ] **5.1** Define query run record schema:
  - `RunId` (GUID)
  - `QueryId`
  - `QueryName`
  - `ContextSnapshot` — bound parameter values at time of run
  - `ExecutedAt`
  - `DurationMs`
  - `Status` (`Success`, `Failed`, `NoResults`)
  - `RowCount`
  - `ErrorMessage` (when Status is Failed)
- [x] **5.2** Implement `Private/Add-XdrQueryRun.ps1` — appends a query run record to the in-memory run history
- [x] **5.3** Populate `Context.Data` with a `QueryRuns` list
- [x] **5.4** Surface recent query runs in the activity log panel

### Workstream 6: Tests

- [x] **6.1** `Tests/Get-XdrQueryCatalog.Tests.ps1` — loader returns all valid query files; skips none silently
- [x] **6.2** `Tests/Test-XdrQuerySchema.Tests.ps1` — validator rejects missing required fields, duplicate IDs, unmatched placeholders
- [x] **6.3** `Tests/Resolve-XdrQueryParameters.Tests.ps1` — bound parameters resolve from context; unresolved required bindings return blocked state
- [x] **6.4** `Tests/Invoke-XdrQueryInterpolation.Tests.ps1` — placeholders are substituted correctly; injection-unsafe values are rejected
- [x] **6.5** `Tests/Invoke-XdrHuntingQuery.Tests.ps1` — builds correct Advanced Hunting API payload; returns normalized result set
- [x] **6.6** `Tests/Add-XdrQueryRun.Tests.ps1` — appends record correctly; all required fields populated

---

## Acceptance Criteria

- [ ] Query catalog loads from `queries/` on startup and populates `Context.Data.QueryCatalog`
- [ ] Schema validation errors surface with file name and reason — no silent skipping
- [ ] Queries with unsatisfied required context show blocked state in the TUI
- [ ] Interpolation substitutes context values into KQL safely (no injection via user-influenced values)
- [ ] Query results display using the `displayColumns` list from the query definition
- [ ] Every query execution is recorded in the in-memory query run history
- [ ] Pivot-back from results updates `Context.Selection.Entity`

---

## Manual Validation Checklist

- [ ] Load the dashboard — verify starter queries appear in the Query Catalog panel
- [ ] Press `Alt+H` — verify the dashboard switches into hunting mode without changing the outer layout
- [ ] Select a query with missing required context — verify blocked state message names the missing key
- [ ] Select an incident and a query that requires `IncidentId` — verify KQL preview shows the resolved ID
- [ ] Press `Alt+X` on a runnable query — verify results appear in the results panel with row count and duration summary
- [ ] Navigate result rows — verify pivot-back sets the selected entity
- [ ] Check the activity log — verify the query run record appears with status and row count
- [ ] Add an invalid JSON file to `queries/` — verify startup surfaces the error with the filename

---

## Implemented Hunting Mode Slice

The current implementation uses the existing dashboard shell and adds a hunting mode toggle instead of introducing permanently visible query columns.

- `Alt+H` toggles hunting mode on and off.
- In hunting mode, the `incidents` pane becomes the Query Catalog.
- In hunting mode, the `incident_details` pane becomes Query Preview.
- In hunting mode, the `alerts` pane becomes the Activity Log for recent query runs.
- In hunting mode, the `alert_details` pane becomes Query Results.
- In hunting mode, the `action_status` pane becomes Query Actions.
- `Alt+X` executes the selected query from hunting mode.

Result-row navigation and pivot-back are still pending.

---

## Query JSON Example

```json
{
  "id": "user-signin-anomalies",
  "name": "User Sign-In Anomalies",
  "description": "Risk sign-in events for the selected user in the last 7 days.",
  "requiredContext": ["UserId"],
  "parameters": [
    {
      "name": "UserId",
      "contextBinding": "UserId",
      "description": "AAD Object ID of the selected user"
    },
    {
      "name": "LookbackDays",
      "contextBinding": null,
      "defaultValue": "7",
      "description": "Number of days to look back"
    }
  ],
  "kql": "AADSignInEventsBeta | where AccountObjectId == '{{UserId}}' | where Timestamp > ago({{LookbackDays}}d) | where RiskLevelDuringSignIn != 'none' | project Timestamp, AccountUpn, RiskLevelDuringSignIn, IPAddress, City, Country",
  "displayColumns": ["Timestamp", "AccountUpn", "RiskLevelDuringSignIn", "IPAddress", "City", "Country"],
  "tags": ["identity", "risk"]
}
```

---

## New Functions

| Function | Visibility | Purpose |
|----------|------------|---------|
| `Get-XdrQueryCatalog` | Private | Loads and returns all valid query definitions from `queries/` |
| `Test-XdrQuerySchema` | Private | Validates a query object against the schema |
| `Resolve-XdrQueryParameters` | Private | Resolves parameter values from current context |
| `Invoke-XdrQueryInterpolation` | Private | Substitutes resolved parameters into KQL placeholders |
| `Invoke-XdrHuntingQuery` | Public | Submits interpolated KQL to Advanced Hunting API and returns results |
| `Add-XdrQueryRun` | Private | Appends a query run record to the in-memory run history |
