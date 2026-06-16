---
name: pwshxdrspectre-pester-tests
description: 'Authoring and running Pester v5 tests for the PwshXDRSpectre PowerShell module. Use when writing new *.Tests.ps1 files, adding regression tests for empty Graph data, asserting against dashboard source text, mocking private helpers via InModuleScope PwshXDRSpectre, or running focused tests with the repo''s preferred Invoke-Pester command. Covers AllowEmptyCollection/AllowEmptyString regression patterns, brittle Contains/regex assertion pitfalls, [ref] parameter mutation tests, and the PowerShell 7 path used to execute the suite.'
---

# PwshXDRSpectre Pester v5 Test Authoring

Repo-specific conventions and gotchas for Pester tests in `src/Tests/`. Generic Pester v5 syntax is covered by `.github/instructions/powershell-pester-5.instructions.md` and is not repeated here.

## When to Use This Skill

- Adding or updating any `src/Tests/*.Tests.ps1` file
- Writing a regression test for a Graph "no data" / empty-array / blank-id binding bug
- Asserting that the dashboard source contains specific PowerShell text (wiring tests)
- Running a single test file or a curated subset for fast feedback
- Mocking `Get-SpectreEscapedText`, `Restore-XdrLiveCachedAlertsForIncident`, or other private module helpers

## How to Run Tests in This Repo

The generic VS Code "run tests" tool sometimes reports "no tests found" for this module. Always invoke Pester directly with an explicit path:

```powershell
& 'C:\Program Files\PowerShell\7.6\7\pwsh.exe' -NoLogo -NoProfile -Command "Invoke-Pester -Path './Tests/<file>.Tests.ps1'"
```

Run from `src/`. For multi-file slices, pass a comma-separated list to `-Path`.

## File Skeleton

Private helpers live behind the module manifest, so call them from inside `InModuleScope PwshXDRSpectre`:

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'My-PrivateFunction' {
    It 'does X when Y' {
        InModuleScope PwshXDRSpectre {
            # arrange / act / assert
        }
    }
}
```

Do not dot-source private `.ps1` files directly; import the module so other private helpers resolve.

## Gotchas

- **Never** assert with `String.Contains` using a double-quoted PowerShell string that contains `$variable`. PowerShell interpolates first and the assertion silently changes meaning. Use a single-quoted literal or `Should -Match` with an escaped regex.
- **Never** read the wrong file in a wiring test. `Update-XdrLiveOuterTabs.ps1` and `Get-XdrLiveOuterTabsHeader.ps1` are different; assert color markup against the helper that actually emits it.
- **Always** add an explicit empty-data regression test when changing a function fed from Graph. The matching production fix is `[AllowEmptyCollection()]` for arrays and `[AllowEmptyString()]` for strings, with an early no-op inside the function.
- **`Should -Not -Throw` alone is not enough** for empty-input regressions. Also assert post-state (`$queue.Count | Should -Be 0`, `$selectedAlert | Should -Be 'existing'`) so a future refactor cannot pass by silently swallowing the call.
- **`[ref]` parameter tests**: pass `([ref]$variable)` and assert against the local `$variable` after the call. Plain parameters mutate copies and produce false positives.
- **Mock `Get-SpectreEscapedText`** when asserting on text shape rather than escaping behavior: `Mock Get-SpectreEscapedText { $Text }` inside the relevant `Describe`/`Context`.
- **Brittle text assertions** are the #1 source of false failures in wiring tests. If a `Contains` fails after a code change, verify the code first, then prefer `Should -Match` over hand-tuning quoted substrings.
- **Test the live dashboard render block by reading source text**, not by invoking it. Wiring assertions live in `Tests/Start-PwshXdrLiveDashboard.Tests.ps1`.

## Regression Test Patterns

### Empty collection accepted by mandatory parameter

```powershell
It 'accepts an empty incident list and leaves the queue empty' {
    InModuleScope PwshXDRSpectre {
        $queue = [System.Collections.Queue]::new()
        $queue.Enqueue([pscustomobject]@{ IncidentId = 'stale' })

        { Add-XdrLiveAlertPreloads -Incidents @() -AlertPreloadQueue $queue -AlertsByIncidentId @{} -AlertLoadJobsByIncidentId @{} } |
            Should -Not -Throw
        $queue.Count | Should -Be 0
    }
}
```

### Blank string id treated as a no-op cache miss

```powershell
It 'returns false when the incident id is blank' {
    InModuleScope PwshXDRSpectre {
        $context = [pscustomobject]@{ Data = [pscustomobject]@{ Alerts = @() }; Selection = [pscustomobject]@{ Alert = $null } }
        $selectedAlert = 'existing'; $selectedAlertIndex = 2

        Restore-XdrLiveCachedAlertsForIncident -IncidentId '' -AlertsByIncidentId @{} -Context $context -SelectedAlertIdByIncidentId @{} -SelectedAlert ([ref]$selectedAlert) -SelectedAlertIndex ([ref]$selectedAlertIndex) |
            Should -BeFalse
        $selectedAlert | Should -Be 'existing'
        $selectedAlertIndex | Should -Be 2
    }
}
```

## Curated Test Slices

- Query catalog/execution: `Invoke-XdrHuntingQuery.Tests.ps1`, `Add-XdrQueryRun.Tests.ps1`, `New-XdrRuntimeContext.Tests.ps1`, `Get-XdrQueryCatalog.Tests.ps1`, `Test-XdrQuerySchema.Tests.ps1`, `Resolve-XdrQueryParameters.Tests.ps1`, `Invoke-XdrQueryInterpolation.Tests.ps1`
- Dashboard render/wiring: `Start-PwshXdrLiveDashboard.Tests.ps1`
- Alert/incident cache: `Restore-XdrLiveCachedAlertsForIncident.Tests.ps1`, `Add-XdrLiveAlertPreloads.Tests.ps1`

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Cannot bind argument to parameter 'X' because it is an empty array/string.` | Production function needs `[AllowEmptyCollection()]` / `[AllowEmptyString()]` plus an early no-op return. |
| Wiring test fails with "Expected $true, but got $false" on a `Contains` check | Variable interpolation in the assertion or wrong source file read. Switch to single-quoted literal or `Should -Match`. |
| `Should -Invoke` reports zero calls | `Mock` was outside `InModuleScope`. Put the mock and the call inside the same `InModuleScope PwshXDRSpectre` block. |
| `runTests` tool reports "no tests found" | Use the explicit `Invoke-Pester -Path` command from this skill. |