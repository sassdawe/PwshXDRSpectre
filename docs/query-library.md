# Query Library

PwshXDRSpectre loads hunting queries from the repository-level `queries/` folder at dashboard startup. Each query is defined as one JSON file, validated before use, and then exposed through `Context.Data.QueryCatalog`.

## How Query Panels Appear

The current live dashboard already has a fixed shell:

- left list column
- center details column
- right action/status column
- header and help rows

The query experience reuses that shell instead of adding three permanently visible new panels.

- `Alt+H` toggles hunting mode on and off.
- Query Catalog appears in the upper-left pane.
- Query Preview appears in the upper-center pane.
- Recent Query Runs appear in the lower-left pane as the activity log.
- Query Results appear in the lower-center pane.
- The right-side panel continues to act as the command/status surface and shows query actions, blocked-state reasons, and execution feedback.
- Exiting hunting mode returns the dashboard to the normal incident, alert, and details views.

In short: the plan is show/hide by workflow mode, not permanently visible extra columns or rows.

## Hunting Mode Shortcuts

- `Alt+H` toggles hunting mode.
- `Up` and `Down` move through the Query Catalog when the catalog pane is active.
- `Enter` on the Query Catalog moves focus to Query Preview.
- `Alt+X` executes the selected query.
- `Tab`, `Shift+Tab`, `PgUp`, and `PgDn` continue to switch focus between the existing panel regions.

## Add a Query

1. Create a new `.json` file under `queries/`.
2. Use a slug for `id`, for example `device-process-tree`.
3. Add the required fields: `id`, `name`, `description`, `requiredContext`, `parameters`, `kql`, and `displayColumns`.
4. For every `{{placeholder}}` in `kql`, add a matching parameter object in `parameters`.
5. If a parameter does not use `contextBinding`, give it a `defaultValue`.
6. Keep `requiredContext` limited to `IncidentId`, `DeviceId`, `UserId`, or `FileHash`.
7. Run the focused tests before committing.

## Supported Schema

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
      "description": "AAD object ID of the selected user"
    },
    {
      "name": "LookbackDays",
      "contextBinding": null,
      "defaultValue": "7",
      "description": "Number of days to look back"
    }
  ],
  "kql": "AADSignInEventsBeta | where AccountObjectId == '{{UserId}}' | where Timestamp > ago({{LookbackDays}}d)",
  "displayColumns": ["Timestamp", "AccountUpn", "RiskLevelDuringSignIn"],
  "tags": ["identity", "risk"]
}
```

## Context Binding Rules

- `IncidentId` resolves from `Context.Selection.Incident.IncidentId`.
- `DeviceId` resolves from `Context.Selection.Entity.DeviceId`.
- `UserId` resolves from `Context.Selection.Entity.UserId`.
- `FileHash` resolves from `Context.Selection.Entity.Sha256`.

If a required binding is missing, the query is blocked and the missing keys are reported back to the caller.

### Passing a `UserId`

`UserId` is currently supplied through context binding, not through a manual parameter prompt.

- Open an incident.
- Move to the incident entities tab.
- Select a user entity that contains `UserId`.
- Enter hunting mode and run a query that requires `UserId`.

If no selected entity exposes `UserId`, the query remains blocked and the preview/action panels will show a hint telling you to select a user entity first.

Manual entry for `UserId` is not implemented yet.

## Validation Rules

- `id` must be unique across the catalog.
- `id` must use slug format.
- `requiredContext` values outside the supported key set are rejected.
- Parameters must define a valid `contextBinding` or a `defaultValue`.
- Every KQL placeholder must match a declared parameter.
- `displayColumns` must contain at least one non-empty column name.

## Safe Interpolation Rules

PwshXDRSpectre rejects unsafe values before substituting them into KQL.

- `IncidentId`, `DeviceId`, and `UserId` currently allow letters, numbers, and hyphens.
- `FileHash` currently allows only alphanumeric characters.

If you add a query that expects a different parameter shape, update the interpolation validation in `Invoke-XdrQueryInterpolation` first.

## Focused Validation Commands

```powershell
Invoke-Pester -Path "src/Tests/Get-XdrQueryCatalog.Tests.ps1","src/Tests/Test-XdrQuerySchema.Tests.ps1","src/Tests/Resolve-XdrQueryParameters.Tests.ps1","src/Tests/Invoke-XdrQueryInterpolation.Tests.ps1","src/Tests/Invoke-XdrHuntingQuery.Tests.ps1","src/Tests/Add-XdrQueryRun.Tests.ps1"
```