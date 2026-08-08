# Localization & RTL — supy_scanner

How the branded scanner UI localizes its copy and mirrors for right-to-left
locales. The library ships **English and Arabic** out of the box and renders RTL
correctly with no work from the retailer.

Scope: this covers the **Flutter chrome** the library draws over the native
camera preview — top bars, guidance cards, confirmation/pick sheets, and the
unsupported-platform placeholder. It does not cover native full-screen surfaces
(document / batch), which localize through their own platform resources.

## The model — one bundle, resolved like the palette

Localized copy works exactly like theming does (`SupyScannerPalette`). There is
one immutable source of default strings, [`SupyScannerStrings`], and every widget
resolves each label as:

```dart
config.field ?? strings.field
```

- **`config.field` wins** when the retailer set it — an explicit string is
  shown verbatim in every locale (it is not translated).
- **`strings.field`** supplies the default when config left the field `null`,
  picked from the bundle for the active locale.

This is the same fallthrough the D2-1 palette work introduced for colors
(`config.color ?? palette.token`), so the two read identically at every call
site. All config string fields are therefore `String?` and default to `null`.

## Choosing the locale

The barcode screen resolves its bundle once, in `build`:

```dart
final strings = SupyScannerStrings.of(
  widget.locale ?? Localizations.maybeLocaleOf(context)?.languageCode,
);
```

Resolution order:

1. **Explicit `locale:`** passed to the screen (additive optional arg — Scanbot
   call sites that never pass one are unaffected).
2. **Ambient `Localizations` locale** from the host app's `MaterialApp`.
3. **English**, if neither is present.

`SupyScannerStrings.of(code)` returns the Arabic bundle for `'ar'` and English
for everything else (including `null` and unknown codes).

## RTL mirroring

Each bundle exposes the layout direction its language implies:

```dart
TextDirection get textDirection =>
    languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;
```

The screen wraps its chrome in a `Directionality` using that value, so Arabic
mirrors automatically. To keep this working, the widgets follow one rule:

> **Use the directional variants for anything the eye reads along the writing
> axis.** `EdgeInsetsDirectional` (`start`/`end`), `AlignmentDirectional`
> (`*Start`/`*End`), and `PositionedDirectional` (`start`/`end`) instead of the
> physical `left`/`right`. Physical insets are only for genuinely
> direction-neutral spacing (symmetric or vertical-only).

Text does not need manual alignment — under the ambient `Directionality`, a
`Text` aligns to the reading edge on its own.

## Overriding copy

Set the relevant field on the use-case / chrome configuration. An explicit
string is shown as-is in all locales:

```dart
SupyMultipleScanUseCaseConfiguration(
  submitButtonText: 'Save', // shown verbatim; not localized
)
```

`SupyTextStyleSpec.text` has three states on the top bar:

- **`null`** → resolve from the bundle (e.g. `strings.cancel`).
- **`''`** (empty) → hide the button.
- **non-empty** → render that exact string.

To rebrand a whole locale at once, pass a bundle assembled with
`SupyScannerStrings.copyWith` rather than overriding fields one screen at a time.

## Adding a locale

1. Add a preset constructor to `SupyScannerStrings` (e.g. `.fr()`) that sets
   every field plus the matching `SupyDocumentGuidanceHints` preset, and extend
   `textDirection` if the new language is RTL.
2. Route it in `SupyScannerStrings.of(...)`.
3. Add bundle coverage in `test/models/supy_scanner_strings_test.dart` (preset
   values, `of()` selection, `textDirection`).
4. If the language is RTL, add a screen-level mirroring test mirroring the
   Arabic case in `test/widgets/supy_barcode_scanner_screen_test.dart`.

## Tests

| What | Where |
|---|---|
| Bundle presets, `of()` selection, direction, format helpers, `copyWith`/equality | `test/models/supy_scanner_strings_test.dart` |
| Config defaults are `null` (so copy falls through to the bundle) | `test/models/supy_*_use_case_configuration_test.dart` |
| `locale: 'ar'` mirrors chrome to RTL and resolves Arabic copy | `test/widgets/supy_barcode_scanner_screen_test.dart` |
| Unsupported-platform placeholder uses the bundle string | `test/widgets/supy_{barcode,document}_scanner_view_test.dart` |

[`SupyScannerStrings`]: ../lib/src/models/ui/supy_scanner_strings.dart
