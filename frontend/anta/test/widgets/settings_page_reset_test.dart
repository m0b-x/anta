import 'dart:async';

import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/constants/label_appearance.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/label_style.dart';
import 'package:anta/models/restore_location_mode.dart';
import 'package:anta/pages/settings_page.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/drawer_host_registry.dart';
import 'package:anta/services/label_appearance_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';

/// The app settings page's Reset to defaults, pinned against today's
/// behaviour before S5 of the settings rework (`docs/settings-rework-roadmap.md`,
/// S13) touches it: every row it owns is read back from the store as its
/// `SettingsKeys.default*`, a row it does not own survives, and the dialog's
/// cancel writes nothing. The label style's repaint is pinned in
/// `settings_page_test.dart`. Since S5 a write that throws stops the chain
/// with an error and the page re-reads the store.
void main() {
  late AppDatabase db;
  late SettingsService settings;
  late _FailingWrites writes;

  final l10n = AppLocalizationsEn();

  /// Every row `_resetToDefaults` writes, as `setUp` moves it.
  final moved = <String, Object>{
    'folderSwipe': !SettingsKeys.defaultFolderSwipeEnabled,
    'noteSwipe': !SettingsKeys.defaultNoteSwipeEnabled,
    'confirmDelete': !SettingsKeys.defaultConfirmDelete,
    'autoSaveEnabled': !SettingsKeys.defaultAutoSaveEnabled,
    'autoSaveInterval': 30,
    'notePreview': !SettingsKeys.defaultShowNotePreview,
    'statsBar': !SettingsKeys.defaultShowStatsBar,
    'haptics': !SettingsKeys.defaultHapticFeedback,
    'restoreMode': RestoreLocationMode.off,
    'liveMarkdown': !SettingsKeys.defaultLiveMarkdownRendering,
    'lineNumbers': !SettingsKeys.defaultShowLineNumbers,
    'wordWrap': !SettingsKeys.defaultWordWrap,
    'cursorLine': !SettingsKeys.defaultShowCursorLine,
    'autoBreak': !SettingsKeys.defaultAutoBreakLongLines,
    'previewWhenHidden': !SettingsKeys.defaultPreviewWhenKeyboardHidden,
    'scrollCursor': !SettingsKeys.defaultScrollCursorOnKeyboard,
    'previewMode': !SettingsKeys.defaultPreviewModeEnabled,
    'previewScrollbar': !SettingsKeys.defaultShowPreviewScrollbar,
    'linesPerChunk': 25,
    'collapsed': {'deprecated'},
    'labelStyle': LabelStyle.stripe,
  };

  /// The same rows as an untouched install reads them.
  final defaults = <String, Object>{
    'folderSwipe': SettingsKeys.defaultFolderSwipeEnabled,
    'noteSwipe': SettingsKeys.defaultNoteSwipeEnabled,
    'confirmDelete': SettingsKeys.defaultConfirmDelete,
    'autoSaveEnabled': SettingsKeys.defaultAutoSaveEnabled,
    'autoSaveInterval': SettingsKeys.defaultAutoSaveInterval,
    'notePreview': SettingsKeys.defaultShowNotePreview,
    'statsBar': SettingsKeys.defaultShowStatsBar,
    'haptics': SettingsKeys.defaultHapticFeedback,
    'restoreMode': RestoreLocationMode.fromName(
      SettingsKeys.defaultRestoreLocationMode,
    ),
    'liveMarkdown': SettingsKeys.defaultLiveMarkdownRendering,
    'lineNumbers': SettingsKeys.defaultShowLineNumbers,
    'wordWrap': SettingsKeys.defaultWordWrap,
    'cursorLine': SettingsKeys.defaultShowCursorLine,
    'autoBreak': SettingsKeys.defaultAutoBreakLongLines,
    'previewWhenHidden': SettingsKeys.defaultPreviewWhenKeyboardHidden,
    'scrollCursor': SettingsKeys.defaultScrollCursorOnKeyboard,
    'previewMode': SettingsKeys.defaultPreviewModeEnabled,
    'previewScrollbar': SettingsKeys.defaultShowPreviewScrollbar,
    'linesPerChunk': SettingsKeys.defaultPreviewLinesPerChunk,
    'collapsed': <String>{},
    'labelStyle': LabelStyle.fromName(SettingsKeys.defaultLabelStyle),
  };

  setUp(() async {
    LabelAppearanceService.reset();
    SettingsService.reset();
    LabelAppearance.style.value = LabelStyle.dot;
    writes = _FailingWrites();
    db = await openTestDatabase(interceptor: writes);
    settings = SettingsService.forTesting(db);
    DrawerHostRegistry.clear();
    GetIt.I.registerSingleton<AuthService>(NoOpAuthService());

    // Every value the reset writes, away from its default — as [moved] lists.
    await settings.setFolderSwipeEnabled(
      !SettingsKeys.defaultFolderSwipeEnabled,
    );
    await settings.setNoteSwipeEnabled(!SettingsKeys.defaultNoteSwipeEnabled);
    await settings.setConfirmDelete(!SettingsKeys.defaultConfirmDelete);
    await settings.setAutoSaveEnabled(!SettingsKeys.defaultAutoSaveEnabled);
    await settings.setAutoSaveInterval(30);
    await settings.setShowNotePreview(!SettingsKeys.defaultShowNotePreview);
    await settings.setShowStatsBar(!SettingsKeys.defaultShowStatsBar);
    await settings.setHapticFeedback(!SettingsKeys.defaultHapticFeedback);
    await settings.setRestoreLocationMode(RestoreLocationMode.off);
    await settings.setLiveMarkdownRendering(
      !SettingsKeys.defaultLiveMarkdownRendering,
    );
    await settings.setShowLineNumbers(!SettingsKeys.defaultShowLineNumbers);
    await settings.setWordWrap(!SettingsKeys.defaultWordWrap);
    await settings.setShowCursorLine(!SettingsKeys.defaultShowCursorLine);
    await settings.setAutoBreakLongLines(
      !SettingsKeys.defaultAutoBreakLongLines,
    );
    await settings.setPreviewWhenKeyboardHidden(
      !SettingsKeys.defaultPreviewWhenKeyboardHidden,
    );
    await settings.setScrollCursorOnKeyboard(
      !SettingsKeys.defaultScrollCursorOnKeyboard,
    );
    await settings.setPreviewModeEnabled(
      !SettingsKeys.defaultPreviewModeEnabled,
    );
    await settings.setShowPreviewScrollbar(
      !SettingsKeys.defaultShowPreviewScrollbar,
    );
    await settings.setPreviewLinesPerChunk(25);
    await settings.setAppSettingsCollapsedSections(const {'deprecated'});
    await settings.setLabelStyle(LabelStyle.stripe);
    // One row the reset does not own: it must survive.
    await settings.setCalendarShowFilterChips(
      !SettingsKeys.defaultCalendarShowFilterChips,
    );
  });

  tearDown(() async {
    DrawerHostRegistry.clear();
    await GetIt.I.reset();
    LabelAppearanceService.reset();
    SettingsService.reset();
    LabelAppearance.style.value = LabelStyle.dot;
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  /// Drift answers on futures `FakeAsync` alone never completes, so real time
  /// and pumped frames are interleaved rather than `pumpAndSettle` used.
  Future<void> settle(WidgetTester tester, {int rounds = 14}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const SettingsPage(),
      ),
    );
    await settle(tester);
  }

  /// Scrolls to the footer's reset button — built only while the search box
  /// is empty, so it is scrolled to rather than filtered to — and answers
  /// its confirm with [answer].
  Future<void> resetAndAnswer(WidgetTester tester, String answer) async {
    await tester.scrollUntilVisible(
      find.text(l10n.resetToDefaults),
      600,
      scrollable: find
          .descendant(
            of: find.byType(SettingsSectionList),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await settle(tester);
    await tester.tap(find.text(l10n.resetToDefaults));
    await tester.pumpAndSettle();
    expect(find.text(l10n.resetToDefaultsConfirm), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(answer));
    await settle(tester);
  }

  /// The rows the reset owns, as the store holds them.
  Future<Map<String, Object>> stored(WidgetTester tester) async {
    final values = await tester.runAsync(
      () async => <String, Object>{
        'folderSwipe': await settings.getFolderSwipeEnabled(),
        'noteSwipe': await settings.getNoteSwipeEnabled(),
        'confirmDelete': await settings.getConfirmDelete(),
        'autoSaveEnabled': await settings.getAutoSaveEnabled(),
        'autoSaveInterval': await settings.getAutoSaveInterval(),
        'notePreview': await settings.getShowNotePreview(),
        'statsBar': await settings.getShowStatsBar(),
        'haptics': await settings.getHapticFeedback(),
        'restoreMode': await settings.getRestoreLocationMode(),
        'liveMarkdown': await settings.getLiveMarkdownRendering(),
        'lineNumbers': await settings.getShowLineNumbers(),
        'wordWrap': await settings.getWordWrap(),
        'cursorLine': await settings.getShowCursorLine(),
        'autoBreak': await settings.getAutoBreakLongLines(),
        'previewWhenHidden': await settings.getPreviewWhenKeyboardHidden(),
        'scrollCursor': await settings.getScrollCursorOnKeyboard(),
        'previewMode': await settings.getPreviewModeEnabled(),
        'previewScrollbar': await settings.getShowPreviewScrollbar(),
        'linesPerChunk': await settings.getPreviewLinesPerChunk(),
        'collapsed': await settings.getAppSettingsCollapsedSections(),
        'labelStyle': await settings.getLabelStyle(),
      },
    );
    return values!;
  }

  Future<bool> filterChips(WidgetTester tester) async =>
      (await tester.runAsync(settings.getCalendarShowFilterChips))!;

  testWidgets('confirmed writes every row it owns back to its default', (
    tester,
  ) async {
    await pumpPage(tester);

    await resetAndAnswer(tester, SemanticsIds.sheetConfirm);

    expect(find.text(l10n.settingsReset), findsOneWidget);
    expect(await stored(tester), defaults);
    // A row another page owns is not this reset's to touch.
    expect(
      await filterChips(tester),
      !SettingsKeys.defaultCalendarShowFilterChips,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancelled keeps every value', (tester) async {
    await pumpPage(tester);
    final before = await stored(tester);

    await resetAndAnswer(tester, SemanticsIds.sheetCancel);

    expect(find.text(l10n.settingsReset), findsNothing);
    expect(await stored(tester), before);
    expect(before, moved);
    expect(
      await filterChips(tester),
      !SettingsKeys.defaultCalendarShowFilterChips,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a write that throws reports the failure, claims no success '
      'and leaves the page showing what the store holds', (tester) async {
    await pumpPage(tester);
    // The label style goes last, through `LabelAppearanceService` — the
    // write S13 found could fail with the page left on stale values.
    writes.failOnKey = SettingsKeys.labelStyle;

    await resetAndAnswer(tester, SemanticsIds.sheetConfirm);

    expect(tester.takeException(), isNull);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text(l10n.settingsResetFailed), findsOneWidget);
    expect(find.text(l10n.settingsReset), findsNothing);
    // Every write before the failing one landed; the order never changed.
    expect(await stored(tester), {
      ...defaults,
      'labelStyle': LabelStyle.stripe,
    });
    // Re-read, not left on the old values: the preview chunk row, folded
    // shut before the reset, is open again and reads its default.
    final chunk = tester.widget<Slider>(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.appSettingsPreviewChunk),
        matching: find.byType(Slider),
      ),
    );
    expect(chunk.value, SettingsKeys.defaultPreviewLinesPerChunk.toDouble());

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('confirmed after the page is gone writes nothing and throws '
      'nothing', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigator = GlobalKey<NavigatorState>();
    final page = MaterialPageRoute<void>(builder: (_) => const SettingsPage());
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const SizedBox.shrink(),
      ),
    );
    unawaited(navigator.currentState!.push(page));
    await tester.pumpAndSettle();
    await settle(tester);
    final before = await stored(tester);

    await tester.scrollUntilVisible(
      find.text(l10n.resetToDefaults),
      600,
      scrollable: find
          .descendant(
            of: find.byType(SettingsSectionList),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await settle(tester);
    await tester.tap(find.text(l10n.resetToDefaults));
    await tester.pumpAndSettle();
    // The page leaves from under its own dialog, as a pop from elsewhere
    // would take it.
    navigator.currentState!.removeRoute(page);
    await tester.pump();
    expect(find.byType(SettingsPage), findsNothing);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sheetConfirm));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(l10n.settingsReset), findsNothing);
    expect(await stored(tester), before);
    expect(before, moved);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('the restore default is the SettingsKeys constant, and it is the '
      'whole chain as before', () async {
    expect(
      RestoreLocationMode.fromName(SettingsKeys.defaultRestoreLocationMode),
      RestoreLocationMode.everything,
    );
    await db.userSettingsDao.deleteValue(SettingsKeys.restoreLocationMode);
    expect(
      await settings.getRestoreLocationMode(),
      RestoreLocationMode.fromName(SettingsKeys.defaultRestoreLocationMode),
    );
  });
}

/// Throws on any insert that writes [failOnKey], so one setter of the reset's
/// chain fails the way a closed or locked database would.
class _FailingWrites extends QueryInterceptor {
  String? failOnKey;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    final key = failOnKey;
    if (key != null && args.contains(key)) {
      return Future.error(StateError('write of $key refused'));
    }
    return super.runInsert(executor, statement, args);
  }
}
