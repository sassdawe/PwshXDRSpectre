# Investigation workflows

Investigation workflows are repository-backed JSON definitions stored in `workflows/`.
They are loaded when the live dashboard starts and appear on the global
**Workflows** tab.

## Navigation

- Use `Alt+3` to open **Workflows**.
- Use `↑` and `↓` in the workflow list to select a matching workflow.
- Use `↑` and `↓` in the steps panel to select a step.
- Press `Enter` on a step or workflow action to mark the selected step complete.
- Use `PgUp`, `PgDn`, or `Tab` to move between workflow panels.

## Definition format

Each workflow is a JSON object with:

- `id`: slug-form unique identifier.
- `name`: display name.
- `description`: short summary.
- `match`: optional `all` or `any`; defaults to `all`.
- `requiredContext`: optional context hints such as `IncidentId`, `AlertId`, or `Entity`.
- `conditions`: one or more match conditions.
- `steps`: ordered investigation guidance.
- `tags`: optional labels.

Supported condition fields are:

- `severity`
- `status`
- `classification`
- `tags`
- `serviceSource`
- `category`
- `entityType`

Supported operators are:

- `equals`
- `notEquals`
- `contains`
- `in`

Steps must include `title` and `guidance`. They may also include `evidence` and
`links` arrays.

## Example

```json
{
  "id": "high-severity-incident-review",
  "name": "High Severity Incident Review",
  "description": "Guided investigation workflow for high severity incidents.",
  "match": "any",
  "requiredContext": ["IncidentId"],
  "conditions": [
    {
      "field": "severity",
      "operator": "equals",
      "value": "high"
    }
  ],
  "steps": [
    {
      "title": "Confirm incident scope",
      "guidance": "Review the incident details, impacted assets, and related alerts before taking containment action.",
      "evidence": ["Incident title", "Severity", "Affected users or devices"]
    }
  ],
  "tags": ["incident", "high-severity", "triage"]
}
```
