---
name: l10n
description: Localization workflow for ANTA - ARB files (en/de/ro), gen-l10n, copy style, and pluralization rules. USE FOR - adding or renaming any user-visible string, changing labels/tooltips/snackbars/dialogs, ICU plural keys, or anything touching lib/l10n. Load together with anta-context.
---

# Localization (en / de / ro)

## Workflow

1. Every user-visible string uses `AppLocalizations.of(context)!.keyName` — never hardcoded Dart strings.
2. Add/rename keys in **all three** ARB files together: `lib/l10n/app_en.arb` (primary source), `app_de.arb`, `app_ro.arb`. Keep the German and Romanian files complete whenever keys change.
3. Regenerate and validate:
   ```powershell
   flutter gen-l10n
   dart analyze lib
   ```
4. Never hand-edit the generated `app_localizations_*.dart` files.
5. Check `untranslated.txt` after gen-l10n — it lists keys missing from de/ro.

## Rules

- **ICU plurals**: Romanian needs the `few` form in addition to `one`/`other` (precedent: the `recurrenceEvery*` keys). Keep `{count}`/placeholder metadata blocks identical across all three ARBs.
- No generic `AppLocalizations.byKey` lookup exists and none should be added — select localized strings via sealed `switch` on the enum/rule type.
- For localized weekday/date names use `intl` (`DateFormat.E(localeName)` etc.), never an N×3 ARB matrix (precedent: `RecurrenceFormatter.weekdayShort`).
- Time formatting respects locale 24h/12h conventions via `intl` (precedent: `EventTimeFormatter.formatRange`).

## Copy style

- Concise, direct, utility-app copy — the user may be mid-workout; labels must be short and instantly recognizable.
- No in-app explanatory text for obvious interactions; prefer tooltips, icons, and settings descriptions.
- Keep domain terms consistent across locales: folders, notes, counters, shortcuts, backup, import/export, auto-save, preview, search, events, categories.
- User-facing errors are always localized; `debugPrint` is fine for internal diagnostics where the file already uses it.
