# dx-format-mapping-codegen

**Status:** planned · **Target:** v1.3.0 · **Effort:** S · **Trace:** docs/SYMBOLOGIES.md / CLAUDE.md "add-symbology" skill

## Problem
Each new barcode format requires a hand edit in `FormatMapper.kt`, `SymbologyMapper.swift`, the Dart enum, and `docs/SYMBOLOGIES.md`. The four touchpoints get out of sync (compat skill exists, but it's still manual).

## Scope
- Single source-of-truth YAML/JSON under `tools/symbologies/`.
- Codegen produces Kotlin enum, Swift enum, Dart enum, and the docs table.
- The `supy-scanner:add-symbology` skill calls the codegen.

## Out of scope
- Code-generating decoder logic.

## Acceptance
- [ ] Generated files are reproducible from the source; CI fails if drift.
- [ ] Adding a new symbology = edit the YAML + run codegen; no other manual edits.

## Dependencies
- Existing `add-symbology` skill flow.

## Source
- `CLAUDE.md` sub-skills section; `docs/SYMBOLOGIES.md`.
