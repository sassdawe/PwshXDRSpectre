# System Patterns

## Architecture
- Module-first layout under `src/`.
- `PwshXDRSpectre.psm1` dot-sources all `Private/*.ps1` and `Public/*.ps1` scripts, exports public functions, and initializes a global runtime context.
- Public functions provide entry points and service-level operations.
- Private functions own runtime state, view-model shaping, layout composition, keyboard routing, action safety, and background job processing.

## Key Patterns
- Shared runtime context created by `New-XdrRuntimeContext`.
- View-model conversion layers isolate raw Graph payloads from render logic.
- Structured operation and error envelopes wrap service and action results.
- Background ThreadJob processing keeps network-bound work off the live render loop.
- Query catalog and query parameter resolution are repository-driven.

## UI Patterns
- Keep physical Spectre layout slots separate from logical workflow panel names.
- Top-level tabs define the active workflow; hidden sub-modes should not contradict the visible tab.
- Rebuild the root dashboard frame when layout shape changes rather than trying to mutate nested panel child data.
- Keep the live dashboard tick entirely inside the main `while ($true)` loop so job processing, key handling, and render updates remain reachable.
- Poll input before any authentication or loading branch can `continue`, and keep a RawUI fallback alongside `[Console]::KeyAvailable`.

## State and Caching Patterns
- Cache expensive results by stable keys.
- Query result cache keys must include resolved parameter context, not only query id.
- Visible alert rebinding should use a stable signature rather than only incident id plus count.
- Selection-driven workflows should rebind visible state from caches keyed by stable ids instead of relying on a single shared current-result variable.

## Testing Patterns
- Pester tests live under `src/Tests/`.
- Focused `Invoke-Pester -Path ...` commands are the reliable validation path for this repo.

## Data and Payload Patterns
- Nested Graph/API payloads may arrive as `Hashtable`, `OrderedDictionary`, or `IDictionary`; use `.Keys -contains <name>` rather than `.Contains(<name>)`.
- Graph-backed helper parameters must tolerate legitimate empty arrays and blank strings where the runtime can naturally produce them.

## Reference Notes
- Detailed logging, troubleshooting, PowerShell pitfalls, and test invocation notes live in `memory-bank/repoOperationalNotes.md`.
