---
name: flutter-principles
description: How Dart and Flutter code is written in ANTA - the conventions the tree already follows (Flutter 3.44, Dart 3.10, flutter_bloc 9, Drift 2.30, get_it 9), the performance idioms on the hot paths, the widget-structure rules, the test patterns (robots, hand-written fakes, in-memory Drift), the error-handling shape, the platform gates for Android, Windows and macOS, and the smells to watch for. Load when writing or reviewing any Dart code, when a widget rebuilds too often or a list is slow, when adding a bloc, service, test or platform branch, and when a reviewer needs the house standard to judge against. Load together with the area skill.
---

# Flutter principles, as this tree practises them

Measured on 2026-10-11 over `lib/` (480 hand-written files, ~152k lines) and `test/` (382 suites). Every rule names the precedent to copy; a change that departs from a precedent says why in the brief or the record.

## 1. Widget structure

- A page is a `StatefulWidget` whose `build` opens with `final l10n = AppLocalizations.of(context)!;`, then a `BlocBuilder` with `state is X` branches, and dispatches with `context.read<XBloc>().add(...)` (`lib/pages/counter_management_page.dart:43-100`). Keep that shape; a new page that needs something else says why.
- Limit rebuilds at the source: `buildWhen` / `listenWhen` with a shared predicate (`lib/utils/bloc_helpers.dart:88`, used at `optimized_folder_content_page.dart:1298`). `BlocSelector` and `context.select` are unused today; prefer them over a `BlocBuilder` that rebuilds a whole page for one field when you add a new consumer.
- Extract a private widget class, not a `Widget _buildX()` method, for anything that has its own state, rebuilds on its own schedule, or can be `const` (`_CounterCard`, `counter_management_page.dart:173`); the framework can skip a `const` widget subtree, never a helper method. Both styles exist (219 helpers, 88 private classes) — new code leans to classes.
- `const` where the constructor allows it (≈3,800 sites). The call-site lint `prefer_const_constructors` is off, so the discipline is yours; a `const` child under a rebuilding parent is the cheapest optimization in the framework.
- Keys: `super.key` on every public widget; `ValueKey` for list items that reorder (`all_notes_page.dart:467`); a `GlobalKey` only where the page must reach into a child's state (the editor, `optimized_note_editor_page.dart:99`).
- `setState` lives in pages and widgets only (0 in bloc/services/utils/controllers — keep it that way). The editor's typing listener rebuilds the page only when the undo/redo flags flip (`optimized_note_editor_page.dart:944-975`): a rebuild on every keystroke is a defect.

## 2. Performance idioms on the hot paths

- Long or unbounded lists: `ListView.builder`, `ReorderableListView.builder`, slivers, or `ScrollablePositionedList.builder` with a `RepaintBoundary` per chunk (the preview, `source_mapped_markdown_view.dart:480,524`). A `SingleChildScrollView` over a `Column` is for short, fixed content; it lays out every child.
- `RepaintBoundary` around what repaints alone (the calendar grid, `calendar_page.dart:1353`); `CustomPainter` for dense drawing (`color_picker_sheet.dart:843`) with `shouldRepaint` comparing fields.
- Caches are bounded: `LruCache` (`lib/utils/lru_cache.dart`) in the note repository, the editor span cache (three caches keyed by records, `markdown_editor_span_cache.dart:15,42`) and the editor wrapper. Never an unbounded `Map` cache on a path that grows with the user's data.
- Debounce in a bloc with `events.debounce(d).switchMap(mapper)` from `bloc_helpers.dart:20` (the search bloc); in a service with one `Timer` field that is cancelled before it is re-armed (auto-save: 5 s debounce, 30 s interval, `auto_save_service.dart:38`; settings writes 400 ms).
- Heavy pure work off the UI isolate goes through `compute` (`folder_search_service.dart:585`); the editor's span builder runs no timers, no `setState`, no notifiers — it diffs segment lists with `identical()` and splices the line index (`markdown_editor_line_index.dart:97,291`). Keep the typing path allocation-light and synchronous.
- `addPostFrameCallback` is for measuring or scrolling after layout, never for state that the build could have computed; check `mounted` inside it.
- Styles and theme are built once: `const` text styles and a process-wide `AppTheme.light()` / `dark()` (`app_theme.dart:156`); never construct a `ThemeData` or a `TextStyle` with new values in a `build` on a hot path.

## 3. State and dependency injection

- State management is `flutter_bloc` with `Bloc` only (14 blocs, no Cubit): a `sealed class XEvent extends Equatable` with `final class` leaves and `const` constructors (`bloc/counter/counter_event.dart:5-20`); a state with `copyWith` and a transient `lastError` (`counter_state.dart:20-75`) or a terminal `XError` state; handlers registered with `on<E>(_onX)` in the constructor, body `try { await service…; emit(…); } catch (e, st) { _logError(…) }` (`counter_bloc.dart:114-136`).
- Blocs are `registerFactory` in `core/di/injection.dart:212`; app-wide services are eager `registerSingleton` with `dispose:` where they hold resources. The 23 `static Future<X> getInstance()` services each register a `DatabaseLifecycle.registerResetHandler` (`database_lifecycle.dart:44`) — a new DB-backed singleton does the same or multi-database switching leaks state.
- Pages reach services through their bloc. The 77 direct `*Service.getInstance()` calls in pages and widgets, and the 7 page or widget files importing `database/` or `repositories/`, are legacy: do not add to them; route a new need through the bloc.
- The editor's typing path is controllers, not blocs: 14 files under `lib/controllers/`, 2 `ChangeNotifier`s, 12 plain classes with injected callbacks (`note_save_coordinator.dart:19`), owned by the page's `State`, built in `initState`, disposed in `dispose` (`optimized_note_editor_page.dart:106-147, 292, 1271`).

## 4. Platform: Android first, Windows and macOS builds must not break

- One gate per capability, not scattered checks: `sync_availability.dart:21` decides whether sync exists on this platform; `injection.dart:145-185` binds sync and alerts to no-op implementations off phones; `window_insets_resync.dart:29` is Android-only by design. A new plugin that only works on a phone gets the same no-op binding so `flutter run -d windows` and `-d macos` keep working.
- `Platform.isX` appears in eight files and `kIsWeb` in ten; before adding a ninth, look for the gate that should own the branch. `defaultTargetPlatform` for UI timing (`optimized_note_editor_page.dart:1238`), `Platform` for OS facilities (`database_settings_page.dart:930` opens a folder with `open` / `explorer` / `xdg-open`).
- Paths come from `path_provider` only: documents → `gym_notes/` (`database/database.dart:157`), temp for exports, support for the alert gateway; never a hand-built platform path.
- There is no desktop-specific layout code yet (no window-size handling, menu bar, hover, scrollbars or keyboard shortcuts beyond the search bar's `Shortcuts`/`Actions` at `note_search_bar.dart:285`). Phone geometry is the design target; a desktop affordance is an explicit, recorded decision, not a drive-by.

## 5. Theme, metrics and copy

- `ThemeData` is built from an explicit `ColorScheme` (`app_theme.dart:13, 65`), never `fromSeed` — a seed cannot reproduce the approved palette. Surfaces come from `SurfaceRoles` (`pageGround`, `rowGroup`, `rowDivider`, `menuSurface`); opacity via `withValues(alpha:)`, never `withOpacity`.
- Numbers come from the role-named metrics: `FormMetrics` (459 reads), `RowMetrics` (214), `AppBarMetrics` (50). The 285 literal `SizedBox` sizes and 125 literal `fontSize`s in pages and widgets are debt, not precedent: a migrated surface carries none.
- Every string is a localized key (1,539 messages, 60 plurals; `AppLocalizations.of(context)!`, or `lookupAppLocalizations(locale)` where there is no context, `main.dart:107`). Bloc error states that carry English literals (38 today) are the exception to retire, not to extend.

## 6. Accessibility and automation

- `Semantics` / `MergeSemantics` / `ExcludeSemantics` where the widget tree does not already express one node per row; every icon button has a `tooltip:` (104 today); `liveRegion` for transient messages (`overlay_snackbar.dart:112`).
- Anything a device script targets carries a `SemanticsIds` entry (283 ids, kebab-case) or an `AutomationId`; tests find by `find.bySemanticsIdentifier` (202 uses). Text scale is read through `MediaQuery.textScalerOf` and the QA seam `QaTextScale` (`core/qa/qa_overrides.dart:20`).

## 7. Tests

- A sheet or page test drives a robot from `test/widgets/support/` (12 robots, 29 suites): finders scoped to the surface, `_tap` that `ensureVisible`s and settles (`quick_alarm_robot.dart:28-44, 86`). A new surface adds a robot before its first test.
- Doubles are hand-written fakes (`_FakeAuthService implements AuthService`, `test/bloc/sync_bloc_test.dart:13`); there is no mocking package and none is added. Bloc tests collect `bloc.stream.listen(states.add)` and `pumpEventQueue()`.
- The database suite runs on `openTestDatabase()` over `NativeDatabase.memory()` (`test/database/support/db_test_support.dart:11`) and asserts plans and statement counts, never timings; benchmarks carry the `benchmark` tag and are skipped by default.
- The environment is faked, not approximated: text scale through `MediaQuery.copyWith(textScaler:)` in `MaterialApp.builder` (`quick_alarm_sheet_test.dart:80`), surface through `tester.view.physicalSize` with `addTearDown(tester.view.reset)`, the keyboard through `tester.view.viewInsets = const FakeViewPadding(bottom: 320)` (`alert_editor_sheet_test.dart:1344`), theme through `AppTheme.light()` / `dark()`, overflow capture through `support/layout_errors.dart`.
- There are no golden tests and no `integration_test/` directory (the dependency is unused); the device layer is the QA harness.

## 8. Errors and logging

- Diagnostics are `debugPrint('[ClassName] message: $e')` (232 sites, no `print`, no `Logger` — `package:logging` is imported once to forward the alarm plugin's records). Catch with the stack when you log it: `catch (e, st)` is the shape to copy (31 sites), `catch (e)` the one to stop adding.
- `installErrorHooks()` (`main.dart:204`) owns `FlutterError.onError` and `ErrorWidget.builder`; there is no `runZonedGuarded`, so an unawaited future's error must be caught where it is spawned (`unawaited(...)` with its own handling, 97 sites).
- The user sees errors through `CustomSnackbar.showError` (`utils/custom_snackbar.dart:21`) with a localized message; a bloc exposes them as a terminal `XError` state or a transient `lastError`.

## 9. Watch for

- Files past 1,500 lines (15; the largest: `event_editor_sheet.dart` 3,014, `calendar_page.dart` 2,694, `optimized_note_editor_page.dart` 2,643, `form_rows.dart` 2,614, `markdown_settings_page.dart` 2,527) — a change there extracts what it touches into a private widget or a controller rather than growing the file.
- `late` (231, 130 in widgets) and `!` on anything but `AppLocalizations.of(context)!`; `dynamic` (166); `this.context` after an `await` (66 sites — `use_build_context_synchronously` is on, keep the `mounted` guard).
- Dead code to remove when touched: `lib/utils/isolate_worker.dart` and `lib/core/types/result.dart` have no importers; `debounce` is defined twice (`bloc_helpers.dart:20` and a private copy at `note_picker_bloc.dart:10`).
- Duplicate ARB keys (`reset`, `restartRequired` in `app_en.arb` and `app_de.arb`) — JSON keeps the last silently; dedupe with the `l10n` skill.
- `analysis_options.yaml` is bare `flutter_lints`; stricter lints (`prefer_const_constructors`, `prefer_final_locals`, `avoid_dynamic_calls`, `strict-casts`) are an owner decision because turning one on touches hundreds of files — propose, never flip in a feature change.
