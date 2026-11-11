---
name: flutter-principles
description: How Dart and Flutter code is written in ANTA - the conventions the tree already follows (Flutter 3.44.2, Dart 3.12.2, flutter_bloc 9, Drift 2.30, get_it 9), the performance idioms on the hot paths, the widget-structure rules, the test patterns (robots, hand-written fakes, in-memory Drift, the golden matrix), the error-handling shape, the platform gates for Android, Windows and macOS, the Dart tooling to reach for, and the smells to watch for. Load when writing or reviewing any Dart code, when a widget rebuilds too often or a list is slow, when adding a bloc, service, test or platform branch, when a toolchain or lint change is proposed, and when a reviewer needs the house standard to judge against. Load together with the area skill.
---

# Flutter principles, as this tree practises them

Checked against the tree on 2026-11-11: about 665 hand-written files under `lib/`, 655 test suites, roughly 15,000 tests. Every rule names a precedent by file and symbol — never by line number, which rots within a week; grep the symbol. A change that departs from a precedent says why in the brief or the record.

## 1. Widget structure

- A page is a `StatefulWidget` whose `build` opens with `final l10n = AppLocalizations.of(context)!;`, then a `BlocBuilder` with `state is X` branches, and dispatches with `context.read<XBloc>().add(...)` (`CounterManagementPage`). Keep that shape; a new page that needs something else says why.
- Limit rebuilds at the source: `buildWhen` / `listenWhen` with a shared predicate (`FolderBlocFilters` in `lib/utils/bloc_helpers.dart`, used by the browser page). `BlocSelector` and `context.select` are still unused; prefer them over a `BlocBuilder` that rebuilds a whole page for one field when you add a new consumer.
- Extract a private widget class, not a `Widget _buildX()` method, for anything that has its own state, rebuilds on its own schedule, or can be `const` (`_CounterCard` in `counter_management_page.dart`); the framework can skip a `const` widget subtree, never a helper method. Both styles exist — new code leans to classes.
- `const` where the constructor allows it. The call-site lint `prefer_const_constructors` is off, so the discipline is yours; a `const` child under a rebuilding parent is the cheapest optimization in the framework.
- Keys: `super.key` on every public widget; `ValueKey` for list items that reorder (`all_notes_page.dart`); a `GlobalKey` only where the page must reach into a child's state (the editor page).
- `setState` lives in pages and widgets only — none in bloc, services, utils or controllers. The editor's typing listener rebuilds the page only when the undo/redo flags flip (`canUndo` in `optimized_note_editor_page.dart`): a rebuild on every keystroke is a defect.

## 2. Performance idioms on the hot paths

- Long or unbounded lists: `ListView.builder`, `ReorderableListView.builder`, slivers, or `ScrollablePositionedList.builder` with a `RepaintBoundary` per chunk (the preview, `source_mapped_markdown_view.dart`). A `SingleChildScrollView` over a `Column` is for short, fixed content; it lays out every child.
- `RepaintBoundary` around what repaints alone (the calendar grid in `calendar_page.dart`); `CustomPainter` for dense drawing (`color_picker_sheet.dart`, the report's charts) with `shouldRepaint` comparing fields.
- Caches are bounded: `LruCache` (`lib/utils/lru_cache.dart`, by count or by weight) in the note repository, the editor span cache (`markdown_editor_span_cache.dart`) and the editor wrapper. Never an unbounded `Map` cache on a path that grows with the user's data.
- Debounce in a bloc with `events.debounce(d).switchMap(mapper)` from `debounce<T>` in `bloc_helpers.dart` (the search bloc); in a service with one `Timer` field that is cancelled before it is re-armed (`AutoSaveService`, the settings writes).
- Heavy pure work leaves the UI isolate through `Isolate.run` with a top-level or static function (`body_cut.dart`, `BackupService.readBackupFile`, `BodySearchIndexer`); the editor's span builder runs no timers, no `setState`, no notifiers — it diffs segment lists with `identical()` and splices the line index (`markdown_editor_line_index.dart`). Keep the typing path allocation-light and synchronous.
- `addPostFrameCallback` is for measuring or scrolling after layout, never for state that the build could have computed; check `mounted` inside it.
- Styles and theme are built once: `const` text styles and a process-wide `AppTheme.light()` / `dark()`; never construct a `ThemeData` or a `TextStyle` with new values in a `build` on a hot path.

## 3. State and dependency injection

- State management is `flutter_bloc` with `Bloc` only (fifteen feature folders under `lib/bloc/`, no Cubit): a `sealed class XEvent extends Equatable` with `final class` leaves and `const` constructors (`counter_event.dart`); a state with `copyWith` and a transient `lastError` (`counter_state.dart`) or a terminal `XError` state; handlers registered with `on<E>(_onX)` in the constructor, each body a `try` around the service call and the `emit`.
- A bloc whose page gates its first frame on an answer stamps each request: `Bloc.emit` drops a state equal to the current one, so the second identical answer never reaches the page (`OptimizedNoteContentLoaded.loadSequence`).
- Blocs are `registerFactory` in `core/di/injection.dart`; app-wide services are eager `registerSingleton` with `dispose:` where they hold resources. Every `static Future<X> getInstance()` service registers a `DatabaseLifecycle.registerResetHandler` after its instance is fully built — a new DB-backed singleton does the same or multi-database switching leaks state (`drift-migrations`).
- Pages reach services through their bloc. The direct `*Service.getInstance()` calls in pages and widgets (about a hundred by grep on 2026-11-11; 77 were counted on 2026-10-11) and the page or widget files importing `database/` or `repositories/` are legacy: do not add to them; route a new need through the bloc.
- The editor's typing path is controllers, not blocs: plain classes and `ChangeNotifier`s under `lib/controllers/` with injected callbacks (`NoteSaveCoordinator`), owned by the page's `State`, built in `initState`, disposed in `dispose`.

## 4. Platform: Android first, Windows and macOS builds must not break

- One gate per capability, not scattered checks: `lib/services/sync_availability.dart` decides whether sync exists on this platform; `injection.dart` binds sync and alerts to no-op implementations off phones; `WindowInsetsResync` is Android-only by design. A new plugin that only works on a phone gets the same no-op binding so `flutter run -d windows` and `-d macos` keep working.
- `Platform.isX` appears in a handful of files; before adding another, look for the gate that should own the branch. `Platform` is for OS facilities (`database_settings_page.dart` opens a folder with `open` / `explorer` / `xdg-open`).
- Paths come from `path_provider` only: documents → `gym_notes/` (`database/database.dart`), temp for exports, support for the alert gateway; never a hand-built platform path.
- There is no desktop-specific layout code yet (no window-size handling, menu bar, hover, scrollbars or keyboard shortcuts beyond the search bar's `Shortcuts`/`Actions`). Phone geometry is the design target; a desktop affordance is an explicit, recorded decision, not a drive-by.

## 5. Theme, metrics and copy

- `ThemeData` is built from an explicit `ColorScheme` (`app_theme.dart`), never `fromSeed` — a seed cannot reproduce the approved palette. Surfaces come from `SurfaceRoles` in `app_colors.dart` (`pageGround`, `rowGroup`, `rowDivider`, `menuSurface`); opacity via `withValues(alpha:)`, never `withOpacity`.
- Numbers come from the role-named metrics: `FormMetrics`, `RowMetrics`, `AppBarMetrics`. The literal `SizedBox` sizes and `fontSize`s left in pages and widgets are debt, not precedent: a migrated surface carries none.
- Every string is a localized key (`AppLocalizations.of(context)!`, or `lookupAppLocalizations(locale)` where there is no context, as `main.dart` does). Bloc error states that carry English literals are the exception to retire, not to extend.

## 6. Accessibility and automation

- `Semantics` / `MergeSemantics` / `ExcludeSemantics` where the widget tree does not already express one node per row; every icon button has a `tooltip:`; `liveRegion` for transient messages (`overlay_snackbar.dart`).
- Anything a device script targets carries a `SemanticsIds` entry (kebab-case, never renamed) or an `AutomationId`; tests find by `find.bySemanticsIdentifier`. Text scale is read through `MediaQuery.textScalerOf` and the QA seam `QaTextScale` (`core/qa/qa_overrides.dart`).

## 7. Tests

- A sheet or page test drives a robot from `test/widgets/support/`: finders scoped to the surface, a `_tap` that `ensureVisible`s and settles (`quick_alarm_robot.dart`). A new surface adds a robot before its first test.
- Doubles are hand-written fakes (`_FakeAuthService implements AuthService` in `test/bloc/sync_bloc_test.dart`); there is no mocking package and none is added. A fake of a stream that replays in production replays too. Bloc tests collect `bloc.stream.listen(states.add)` and `pumpEventQueue()`.
- The database suite runs on `openTestDatabase()` over `NativeDatabase.memory()` (`test/database/support/db_test_support.dart`) and asserts plans and statement counts, never timings; benchmarks carry the `benchmark` tag and are skipped by default.
- The environment is faked, not approximated: text scale through `MediaQuery.copyWith(textScaler:)` in `MaterialApp.builder`, surface through `tester.view.physicalSize` with `addTearDown(tester.view.reset)`, the keyboard through `tester.view.viewInsets = const FakeViewPadding(bottom: …)`, theme through `AppTheme.light()` / `dark()`, overflow capture through `support/layout_errors.dart`.
- The visual matrix is committed and part of the default run: `test/goldens/` draws the main surfaces with real fonts at three cells of theme × locale × text scale × phone size (`golden_matrix.dart`) under an anti-aliasing-tolerant comparator; a layout regression fails the gate with a diff in `test/goldens/failures/`. After an intended visual change run `flutter test test/goldens --update-goldens` and look at the PNGs. A new main surface joins the matrix; a designer's scratch render stays uncommitted (`ui-language/references/render-recipe.md`).
- There is no `integration_test/` directory (the dependency is unused); the device layer is the QA harness.

## 8. Errors and logging

- Diagnostics are `debugPrint('[ClassName] message: $e')` — no `print`, no `Logger` (`package:logging` is imported once to forward the alarm plugin's records). Catch with the stack when you log it: `catch (e, st)` is the shape to write; the bare `catch (e)` that most older handlers use is the one to stop adding.
- `installErrorHooks()` in `main.dart` owns `FlutterError.onError` and `ErrorWidget.builder`; there is no `runZonedGuarded`, so an unawaited future's error must be caught where it is spawned (`unawaited(...)` with its own handling).
- The user sees errors through `CustomSnackbar.showError` with a localized message; a bloc exposes them as a terminal `XError` state or a transient `lastError`.

## 9. Tools to reach for

- `dart analyze lib` is the gate; while iterating, the Dart MCP's `analyze_files` checks only the files you touched, and its `lsp` tool resolves a symbol's definition and references exactly where a grep over a common name returns noise.
- A dependency's behaviour is read from its source, not recalled: `read_package_uris` / `rip_grep_packages` (Dart MCP) open the resolved version in the pub cache; `pub_dev_search` before proposing a package — and a new package is an owner decision.
- `flutter test --reporter failures-only` prints only failures and the final count line; the default compact reporter floods a captured run with progress lines. A single file or `--plain-name` case while iterating, the whole suite once at the gate.
- Hot reload, runtime errors and the widget tree come through the Dart MCP against a `qa run` (`qa-emulator/references/dart-mcp.md`).
- Flutter's official agent plugin (`flutter/agent-plugins`) is not installed, on purpose: its skills are generic set-up recipes (routing with `go_router`, localization, `http`, JSON) for choices this tree has already made differently.

## 10. Toolchain

- The tree is on Flutter 3.44.2 / Dart 3.12.2 with a `^3.10.4` language floor. The current stable is 3.47 (3.47.8 on 2026-11-10, a security fix among its patches), and 3.50, not yet stable, moves Material and Cupertino into the `material_ui` / `cupertino_ui` packages. An SDK upgrade is an owner decision with its own record: 3.47 changes how `header` and `headingLevel` semantics reach Android and iOS (the `AppBarHeading` work and the device passes read them) and removes `describeEnum` (unused here), and the golden masters will need a re-draw and a look. docs.flutter.dev documents the newest stable — trust the local SDK source when they differ.
- `analysis_options.yaml` is bare `flutter_lints`; stricter lints (`unawaited_futures`, `prefer_const_constructors`, `prefer_final_locals`, `avoid_dynamic_calls`, `strict-casts`) are an owner decision because turning one on touches hundreds of files — propose, never flip in a feature change.

## 11. Watch for

- Files past 1,500 lines (26 on 2026-11-11, up from 15 a month earlier; the largest: `calendar_overview_page.dart` 4,093, `form_rows.dart` 3,698, `optimized_note_editor_page.dart` 3,672, `event_editor_sheet.dart` 3,328) — a change there extracts what it touches into a private widget or a controller rather than growing the file.
- `late` and `!` on anything but `AppLocalizations.of(context)!`; `dynamic`; `this.context` after an `await` (`use_build_context_synchronously` is on, keep the `mounted` guard).
- A singleton that stores `_instance` before its first `await` hands a half-built instance to a concurrent caller. Copy `SettingsService.getInstance`: one memoized in-flight open, the instance published only when it is whole. Five services still publish early and are fixed when touched (`drift-migrations`, "DatabaseLifecycle contract").
- Dead code to remove when touched: `lib/core/types/result.dart` has no importers; `debounce` is defined twice (`bloc_helpers.dart` and a private `_debounce` in `note_picker_bloc.dart`).
