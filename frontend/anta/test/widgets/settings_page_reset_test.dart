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
/// `settings_page_test.dart`.
void main() {
  late AppDatabase db;
  late SettingsService settings;

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
    // A literal in the page, not a `SettingsKeys` default (S13).
    'restoreMode': RestoreLocationMode.everything,
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
    db = await openTestDatabase();
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
}
