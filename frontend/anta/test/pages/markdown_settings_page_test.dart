import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/config/default_markdown_shortcuts.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/pages/markdown_settings_page.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/markdown_bar.dart';
import 'package:anta/widgets/settings_search_field.dart';

/// The shortcut list shows a default by its localized name, and the search
/// reads that name: a German reader sees and finds "Fett" and is never shown
/// the English seed the row was stored under, which the search still reads.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;

  setUpAll(() async {
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

  testWidgets('the pin switch unpins undo and redo in the preview and '
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

    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(previewPins(), isTrue);

    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await settle(tester);

    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(previewPins(), isFalse);
    final settings = await SettingsService.getInstance();
    expect(await tester.runAsync(settings.getToolbarUndoRedoPinned), isFalse);

    await tester.runAsync(() => settings.setToolbarUndoRedoPinned(true));
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
}
