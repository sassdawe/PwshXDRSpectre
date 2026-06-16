# Skill Coverage Validation

## Source
Validated against `docs/copilot-memory-export.md` on 2026-06-16.

## Coverage Summary
- `.github/skills/pwshxdrspectre-powershell/SKILL.md` covers the bulk of the exported repo guidance: state mutation rules, keyboard handling, lazy loading, cache-key design, alert-signature rebinding, Graph payload quirks, logging paths, and troubleshooting patterns.
- `.github/skills/pwshxdrspectre-spectre-layout/SKILL.md` covers the layout-specific subset: slot versus logical naming, panel replacement, dynamic width calculations, theme conventions, and markup-safe rendering.
- `.github/skills/pwshxdrspectre-threadjobs/SKILL.md` covers background job rules: lean view models, argument-list pitfalls, in-flight deduplication, cache rebinding, and alert/query job logging.
- `.github/skills/pwshxdrspectre-pester-tests/SKILL.md` covers the exported testing guidance: explicit `Invoke-Pester -Path` usage, empty-data regressions, `[ref]` mutation tests, and source-text wiring assertions.

## Validation Outcome
- No repo-relevant gaps were found between the exported repository memory and the current repo skill set.
- User-scoped tooling preferences from the export were not copied into repo skills because they are not repo-specific skill content.

## Maintenance Rule
- When new durable repo lessons are added to memory, update both the relevant skill file and `memory-bank/repoOperationalNotes.md` if the guidance is operationally important across sessions.
