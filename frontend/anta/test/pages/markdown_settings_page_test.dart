import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/config/default_markdown_shortcuts.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/utility_button_definition.dart';
import 'package:anta/pages/markdown_settings_page.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/markdown_bar.dart';
import 'package:anta/widgets/settings_search_field.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../goldens/support/golden_fonts.dart';

/// The shortcut list shows a default by its localized name, and the search
/// reads that name: a German reader sees and finds "Fett" and is never shown
/// the English seed the row was stored under, which the search still reads.
/// Beside it: the toolbar's pin, the money rows yielding their value at
/// de 2.0 on the small phone, the vocabulary trigger, and every id a flow
/// reaches (S6 of the settings rework).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;

  setUpAll(() async {
    // Measured with Roboto: the test font's square glyphs are about twice as
    // wide, and would report overflows no device shows (the bar selector's
    // German menu).
    await loadGoldenFonts();
    tempDir = await Directory.systemTemp.createTemp('anta_markdown_settings');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    // Opened here, in real async: inside `testWidgets` the database answers
    // on a background isolate that `FakeAsync` never lets run.
    final db = await AppDatabase.getInstance();
    await db.customSelect('SELECT 1').get();
    await SettingsService.getInstance();
    barBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.getInstance(),
    );
  });

  tearDownAll(() async {
    await barBloc.close();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Hands the real event loop back so the page's settings reads land,
  /// then flushes their `setState`s into frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(412, 6000),
    double textScale = 1.0,
  }) async {
    // Phone-wide and tall: the width is the larger phone's (412 dp), so the
    // German captions that once overflowed their rows are laid out as a
    // user sees them (an overflow throws here); the height is tall so the
    // whole page is built and the shortcut list below the other sections
    // exists.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider<MarkdownBarBloc>.value(
        value: barBloc,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: MarkdownSettingsPage(
            allShortcuts: DefaultMarkdownShortcuts.shortcuts,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> search(WidgetTester tester, String query) async {
    // The utility section has a search field of its own.
    final hint = lookupAppLocalizations(const Locale('de')).searchShortcuts;
    final field = find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is SettingsSearchField && widget.hint == hint,
      ),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.enterText(field, query);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a default shows its localized name, and the search finds it '
      'by that name', (tester) async {
    await pumpPage(tester);
    final de = lookupAppLocalizations(const Locale('de'));
    expect(de.bold, 'Fett');
    Finder row(String label) =>
        find.descendant(of: find.byType(Card), matching: find.text(label));

    expect(row(de.bold), findsOneWidget);
    expect(row(de.italic), findsOneWidget);
    expect(row('Bold'), findsNothing, reason: 'never the stored seed');

    await search(tester, 'Fett');

    expect(row(de.bold), findsOneWidget, reason: 'the bold row');
    expect(row(de.italic), findsNothing);

    // The stored seed is searched beside the shown name (the page's own
    // decision), so the English word still finds the row — under its
    // German name.
    await search(tester, 'Bold');

    expect(row(de.bold), findsOneWidget);
    expect(row(de.italic), findsNothing, reason: 'the search still narrows');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the pin switch pins undo and redo in the preview and '
      'persists', (tester) async {
    await pumpPage(tester);
    final de = lookupAppLocalizations(const Locale('de'));
    final toggle = find.descendant(
      of: find
          .ancestor(of: find.text(de.pinUndoRedo), matching: find.byType(Row))
          .first,
      matching: find.byType(Switch),
    );
    bool previewPins() =>
        tester.widget<MarkdownBar>(find.byType(MarkdownBar)).pinUndoRedo;

    // Unpinned by default since 2026-10-30; the switch is the way back.
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(previewPins(), isFalse);

    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await settle(tester);

    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(previewPins(), isTrue);
    final settings = await SettingsService.getInstance();
    expect(await tester.runAsync(settings.getToolbarUndoRedoPinned), isTrue);

    await tester.runAsync(
      () => settings.setToolbarUndoRedoPinned(
        SettingsKeys.defaultToolbarUndoRedoPinned,
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('at 360 dp and text scale 2.0 the toolbar section and its pin '
      'switch lay out without overflow', (tester) async {
    await pumpPage(tester, size: const Size(360, 780), textScale: 2.0);
    final de = lookupAppLocalizations(const Locale('de'));
    final page = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first;

    for (final label in [de.toolbarLayout, de.pinUndoRedo]) {
      await tester.scrollUntilVisible(find.text(label), 100, scrollable: page);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: label);
      expect(find.text(label).hitTestable(), findsOneWidget, reason: label);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  /// The row a `Semantics` wrapper names by [identifier].
  Finder idRow(String identifier) => find.byWidgetPredicate(
    (widget) =>
        widget is Semantics && widget.properties.identifier == identifier,
  );

  testWidgets('at 360 dp and text scale 2.0 each money row stacks its value '
      'under its description', (tester) async {
    await pumpPage(tester, size: const Size(360, 780), textScale: 2.0);
    final page = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first;

    for (final identifier in [
      SemanticsIds.markdownMoneyStart,
      SemanticsIds.markdownMoneySymbol,
    ]) {
      final row = idRow(identifier);
      await tester.scrollUntilVisible(row, 100, scrollable: page);
      await settle(tester);
      final tile = tester.widget<SettingsYieldingTile>(
        find.descendant(of: row, matching: find.byType(SettingsYieldingTile)),
      );
      final title = find.descendant(
        of: row,
        matching: find.byWidget(tile.title),
      );
      final description = find.descendant(
        of: row,
        matching: find.byWidget(tile.subtitle!),
      );
      final value = find.descendant(of: row, matching: find.text(tile.value!));

      expect(tester.takeException(), isNull, reason: identifier);
      expect(
        tester.getTopLeft(value).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(description).dy - 0.5),
        reason: identifier,
      );
      expect(
        tester.getTopLeft(value).dx,
        moreOrLessEquals(tester.getTopLeft(title).dx, epsilon: 0.5),
        reason: identifier,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('every row and menu a flow reaches carries its id', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    // The bar selector and its ⋮ are drawn once the bars have loaded.
    await tester.runAsync(() async {
      if (barBloc.state is MarkdownBarLoaded) return;
      barBloc.add(const LoadMarkdownBar());
      await barBloc.stream.firstWhere((s) => s is MarkdownBarLoaded);
    });
    // Tall enough that the lazy shortcut list builds every row.
    await pumpPage(tester, size: const Size(412, 12000));
    bool showsId(String identifier) =>
        find.bySemanticsIdentifier(identifier).evaluate().isNotEmpty;

    for (final id in [
      SemanticsIds.settingsBarMarkdown,
      SemanticsIds.markdownSettingsList,
      SemanticsIds.markdownBarMenu,
      SemanticsIds.markdownProfileMenu,
      SemanticsIds.markdownVocabularyTrigger,
      SemanticsIds.markdownMoneyStart,
      SemanticsIds.markdownMoneySymbol,
      SemanticsIds.markdownPerNoteCurrency,
      for (final utility in UtilityButtonDefinition.all)
        SemanticsIds.markdownUtility(utility.id),
      for (final shortcut in DefaultMarkdownShortcuts.shortcuts) ...[
        SemanticsIds.markdownShortcutRow(shortcut.id),
        SemanticsIds.markdownShortcutVisibility(shortcut.id),
        SemanticsIds.markdownShortcutMenu(shortcut.id),
      ],
    ]) {
      expect(showsId(id), isTrue, reason: id);
    }

    // The per-note bars entry lives in the bar selector's ⋮.
    final profileMenu = find.bySemanticsIdentifier(
      SemanticsIds.markdownProfileMenu,
    );
    await tester.ensureVisible(profileMenu);
    await tester.pump();
    await tester.tap(profileMenu);
    await tester.pumpAndSettle();
    expect(showsId(SemanticsIds.markdownPerNoteBars), isTrue);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    handle.dispose();
  });

  testWidgets('a trigger picked under the vocabulary trigger row is shown '
      'selected and persists', (tester) async {
    await pumpPage(tester);
    final row = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.identifier ==
              SemanticsIds.markdownVocabularyTrigger,
    );
    final segments = find.descendant(
      of: row,
      matching: find.byType(SegmentedButton<String>),
    );
    expect(tester.widget<SegmentedButton<String>>(segments).selected, {
      SettingsKeys.defaultVocabularyTriggerChar,
    });

    final colon = find.descendant(of: row, matching: find.text(':'));
    await tester.ensureVisible(colon);
    await tester.pump();
    await tester.tap(colon);
    await settle(tester);

    expect(tester.widget<SegmentedButton<String>>(segments).selected, {':'});
    final settings = await SettingsService.getInstance();
    expect(await tester.runAsync(settings.getVocabularyTriggerChar), ':');

    await tester.runAsync(
      () => settings.setVocabularyTriggerChar(
        SettingsKeys.defaultVocabularyTriggerChar,
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
