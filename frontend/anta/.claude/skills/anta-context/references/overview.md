# ANTA overview

Reference, not rules — moved verbatim from `COPILOT_CONTEXT.md` on 2026-10-11 (sections: Product Purpose, Core User Workflows, Non-Negotiable Rules, Current Stack, Architecture Shape, Error Handling And State, Good Defaults For New Tracking Features). Read only the part the task needs.

## Product Purpose
ANTA is an offline-first Flutter app for tracking the things a person keeps coming back to — training sessions, spending, appointments, and the notes around them. Folders and markdown notes are the substrate; the money ledger, the calendar, and counters are built on top of them, all derived from or stored alongside note content rather than living in separate silos.

The app began as a training log, and that origin still sets the bar. When changing the app, optimize for capture in the middle of something else:
- Users should be able to record a value, a line, a transaction, or an event with minimal friction — mid-set, at a checkout, or between meetings.
- Editing must feel reliable when attention is elsewhere: no lost text, no surprising navigation, no heavy UI while typing.
- Organization should support real habits: folders for programs, projects, months, or topics; notes for sessions/templates/records; counters for global or per-note metrics.
- Offline data ownership matters. Preserve local SQLite data, backup/restore behavior, and future sync readiness.
- UI should be practical, touch-friendly, and quick to scan one-handed. Prefer clear controls, high contrast, stable layouts, and small but obvious status feedback.
- When two designs are otherwise equal, pick the one that survives one-handed use.

## Core User Workflows
- Create folders/subfolders for programs, routines, exercises, weeks, muscle groups, projects, or months.
- Create and edit markdown notes for sessions, templates, logs, measurements, spending, and history.
- Use custom markdown toolbar shortcuts for fast entry of headings, lists, checkboxes, tables, dates, and repeated structures.
- Record spending inline with money-ledger lines that fold into a running balance derived purely from note content.
- Track numeric progress with counters, including global counters and per-note counters with pinning and manual ordering.
- Plan and review with the calendar: categorized events, recurrence, computed holidays and fasting calendars, day summaries, note links.
- Search across notes and within the active note, including regex/whole-word options in the editor search overlay.
- Switch databases, export/import backups, and keep localized app text in English, German, and Romanian.

## Non-Negotiable Rules
- Use `AppLocalizations` for every user-visible string. Update `lib/l10n/app_en.arb`, `app_de.arb`, and `app_ro.arb` together, then run `flutter gen-l10n`.
- Do not hand-edit generated files such as `lib/database/database.g.dart` or generated localization Dart files.
- After changing Drift tables, DAOs, migrations, or database annotations, run `dart run build_runner build --delete-conflicting-outputs`.
- Keep generated schema/migration changes compatible with existing local user data. Add migrations instead of resetting storage.
- Tests are welcome (standing permission, 2026-08-16). Comments carry the why, never the what: `///` on public members and non-obvious decisions, never narration of the code (rule rewritten 2026-09-26). No new markdown files or broad refactors unless explicitly requested; a design record for a UI rework is explicitly requested (the `ui-revamp` skill).
- Preserve existing user data semantics: soft deletes, CRDT fields, positions, sort preferences, pinned counters, note assignments, and backup format compatibility.
- Keep changes focused and consistent with the local style. Avoid introducing new state-management, persistence, or navigation patterns without a strong reason.
- **Every bottom sheet pads its own bottom, and it is the LARGER of the keyboard inset and the system inset.** `showModalBottomSheet(useSafeArea: true)` wraps the route in `SafeArea(bottom: false)` — it guards the status bar and deliberately **not** the gesture pill / three-button bar — so a sheet that pads by `viewInsets.bottom` alone looks perfect with the keyboard up and runs underneath the navigation bar without it. This has now been shipped-and-fixed **five separate times** (six sheets on 2026-08-25, `EventDescriptionSheet` on 2026-08-31, `ColorPickerSheet` on 2026-09-02, `BarSwitcherSheet` on 2026-10-01 — whose list ended under the navigation bar — along with the pairing sheet, which *added* the two insets and so floated a navigation bar above the keyboard), so treat it as a checklist item on any new sheet, not a thing to notice in review:
  ```dart
  final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
  final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
  final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;
  ```
  Apply it to the **scrollable's bottom padding**, or to the **whole sheet** when a fixed footer (an action row, a docked markdown bar) sits below the scroll view. A `const EdgeInsets` can never be right here, which is exactly how the earlier regressions passed review. Then add the sheet to [test/widgets/sheet_bottom_clearance_test.dart](test/widgets/sheet_bottom_clearance_test.dart) — it fakes a 48px nav bar and fails if the padding does not respond, and it is the only thing that has actually caught this.

## Current Stack
- Flutter app with Dart SDK `^3.10.4`, Material 3, and `flutter_lints`.
- State management: `flutter_bloc` with `Equatable` states/events.
- Persistence: Drift SQLite, `sqlite3_flutter_libs`, `path_provider`, `shared_preferences`.
- DI: `get_it` via `lib/core/di/injection.dart`.
- Editor/markdown: local `packages/re_editor` with a custom line-based markdown renderer (`lib/utils/line_based_markdown_builder.dart`).
- Search/debounce: `stream_transform`, FTS5, isolate-backed indexing utilities.
- Sharing/import: `share_plus`, `file_picker`.
- External links: `url_launcher` (markdown preview hyperlinks open via `LaunchMode.externalApplication`; only `http`, `https`, `mailto`, `tel` schemes are accepted).
- Localization: Flutter gen-l10n with locales `en`, `de`, `ro`.

## Architecture Shape
Follow the existing flow:

```text
Page/Widget -> BLoC -> Service -> Repository -> DAO -> Drift database
```

- BLoCs live under `lib/bloc/` and should stay thin: route events, manage loading/error states, and delegate business logic to services.
- Services in `lib/services/` own app workflows such as note storage, folder storage, search indexing, counters, settings, backup/restore, database switching, auto-save, and note positions.
- Repositories in `lib/repositories/` provide cached/reactive access over DAOs. Invalidate caches carefully after creates, updates, deletes, moves, and reorder operations.
- DAOs in `lib/database/daos/` own SQL/Drift details, transactions, soft deletes, pagination, FTS, and migrations support.
- Models in `lib/models/` generally use `Equatable`, `copyWith`, and JSON keys from `lib/constants/json_keys.dart`.
- Constants belong in `lib/constants/`. Prefer existing spacing, text style, icon size, settings key, and app constant files over magic values.

## Error Handling And State
- Prefer existing sealed/result-style patterns where available, but match the exact style in the target BLoC or service.
- Keep BLoC states immutable and `Equatable` where that is already the local pattern.
- Complete provided `Completer`s on success and error where events expose them.
- Use `debugPrint` for internal diagnostics where the file already does; user-facing errors must be localized.
- Avoid swallowing persistence failures in code paths where data loss could result. Surface save/import/export errors clearly.
- **`main.dart` installs the app's error hooks before anything else** (`installErrorHooks()`, right after `WidgetsFlutterBinding.ensureInitialized()`): `ErrorWidget.builder` becomes `buildAppErrorWidget`, and `FlutterError.onError` keeps `FlutterError.presentError` and adds one `debugPrint` line carrying the library, the context and the exception — the only thing a release build surfaces in logcat. Flutter's own release `ErrorWidget` is a **textless grey `RenderErrorBox` that expands to fill its parent and absorbs taps**, so a single build exception inside a bottom sheet is indistinguishable from a blank, dead sheet; the replacement says what happened, stays as small as its content (`Align` + `ConstrainedBox` + `mainAxisSize: min`) and hit-tests nothing outside its own box. It runs with **no guaranteed inherited theme, directionality or `BuildContext`**, so it supplies its own `Directionality` + `Material`, uses explicit colours from `AppColors`, and resolves localizations through `lookupAppLocalizations(platformDispatcher.locale)` guarded by `AppLocalizations.supportedLocales` (English fallback, then plain literals). `runApp` is **not** wrapped in `runZonedGuarded` — the binding, Firebase and `configureDependencies()` all run in the root zone before it, and moving only `runApp` into a child zone splits zone-sensitive setup. Guard: `test/widgets/app_error_widget_test.dart`.

## Good Defaults For New Tracking Features
- If a feature captures user data, decide whether it belongs in note markdown, a counter, settings, or database schema before adding new storage.
- Prefer note-level features when the data is naturally part of a session or entry, and counter features when the value needs repeated numeric updates or cross-note aggregation. Derived-from-content features (the money ledger is the reference case) beat a parallel store that can drift.
- Preserve backup/export support for any persisted user data.
- Make sorting, pinning, and reordering explicit when users are likely to curate the information manually.
- Keep input flows fast: sensible defaults, remembered choices, localized validation, and no unnecessary dialogs.
