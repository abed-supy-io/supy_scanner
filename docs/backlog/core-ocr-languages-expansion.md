# core-ocr-languages-expansion

**Status:** planned · **Target:** v1.3.0 · **Effort:** M · **Trace:** docs/LOCALIZATION.md follow-up

## Problem
`OcrRunner` is wired for `en` + `ar`. Retailer expansion into FR/ES/DE markets requires additional ML Kit Text Recognition / Vision language packs and the prewarm hooks need to match.

## Scope
- Surface `SupyOcrLanguage.{en, ar, fr, es, de}` (enum, not free string) in `SupyScanOptions`.
- Plumb to ML Kit's language-pack selection on Android and Vision recognition languages on iOS.
- Update `prewarm` to optionally warm the requested set.

## Out of scope
- Handwriting / table extraction (separate future ticket).
- CJK languages — ML Kit's CJK packs need a separate sizing decision.

## Acceptance
- [ ] OCR returns non-empty text on a fixture per added language.
- [ ] Prewarm respects the configured set and doesn't fetch unused packs.

## Dependencies
- `docs/LOCALIZATION.md`.

## Source
- `docs/LOCALIZATION.md`; current `OcrRunner` implementation.
